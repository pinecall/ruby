# frozen_string_literal: true

module Pinecall
  class Client
    # Reading a log: the same URL as a JSON page and as a stream, folded by the protocol's reducer.
    #
    # The cursor is the whole protocol. A stream that drops is the same URL again with a fresher
    # `Last-Event-ID`, and the platform answers a reader that fell behind with `log.gap` — carrying
    # a snapshot when it has one — then `log.caught_up` when what follows is live.
    module Observe
      # One page of a log: the entries after the cursor, what they fold to, and where to go next.
      Page = Data.define(:entries, :state, :live, :next)

      # One entry, what it means, and the state the log has folded to including it.
      Observation = Data.define(:entry, :event, :state)

      RETRY_S = 1.0
      LONGEST_RETRY_S = 30.0

      module_function

      # The log as it stands: one page after the cursor, what it folds to, and whether more
      # follows. The page says where to go next itself, because an empty page of a live log still
      # has a next and a reader must not have to infer one from the last entry it happened to get.
      def history(target, url:, api_key:, after: 0)
        answer = get(target, url:, api_key:, after:, accept: "application/json")
        page = JSON.parse(answer.body, symbolize_names: true)
        raise Error, "the log page is not { entries, live, next }" unless page.is_a?(Hash) && page[:entries].is_a?(Array)

        entries = page[:entries].map { |raw| Protocol.decode_entry(raw) }
        Page.new(entries:, state: Protocol.reduce(entries), live: page[:live] == true,
                 next: page[:next].is_a?(Integer) ? page[:next] : nil)
      end

      # A log as it happens: every entry after the cursor, then everything that follows, forever.
      # Yields an Observation per entry. Returns when the block breaks or `stop` is called.
      def observe(target, url:, api_key:, after: 0, stop: nil)
        state = Protocol.initial_state
        attempt = 0
        opened = false
        until stop&.call
          begin
            stream(target, url:, api_key:, after:) do |entry|
              attempt = 0
              opened = true
              after = entry.seq
              state = Protocol.apply(state, entry)
              yield Observation.new(entry:, event: Protocol.event_of(entry), state:)
            end
          rescue StandardError
            # A stream that never opened is a misconfiguration — a wrong key, a call nobody has —
            # and the reader hears it now. One that dropped after it worked is what the cursor is
            # for, and coming back is not news.
            raise unless opened
          end
          attempt += 1
          sleep([LONGEST_RETRY_S, RETRY_S * (2**(attempt - 1))].min * rand)
        end
      end

      # One connection's worth of entries, until the server closes it.
      def stream(target, url:, api_key:, after:)
        get(target, url:, api_key:, after:, accept: "text/event-stream") do |answer|
          buffered = +""
          answer.read_body do |chunk|
            buffered << chunk
            while (cut = buffered.index("\n\n"))
              block = buffered.slice!(0, cut + 2)
              entry = entry_in(block)
              yield entry unless entry.nil?
            end
          end
        end
      end

      # One SSE block as an entry, or nil for a comment or a keep-alive that carries no data.
      def entry_in(block)
        data = block.lines.filter_map { |line| line.delete_prefix("data:").lstrip.chomp if line.start_with?("data:") }
        return nil if data.empty?

        Protocol.decode_entry(JSON.parse(data.join("\n"), symbolize_names: true))
      end

      def get(target, url:, api_key:, after:, accept:, &block)
        where = URI.parse(door(target, url))
        where.query = URI.encode_www_form(after:) if after.positive?
        request = Net::HTTP::Get.new(where)
        request["accept"] = accept
        request["authorization"] = "Bearer #{api_key}"
        request["last-event-id"] = after.to_s if after.positive?
        answer(where, request, &block)
      end

      def answer(where, request)
        http = Net::HTTP.new(where.host, where.port)
        http.use_ssl = where.scheme == "https"
        http.read_timeout = nil
        http.start do |open|
          open.request(request) do |response|
            raise Error, "#{where.path}: the gateway answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

            return block_given? ? yield(response) : response.tap(&:body)
          end
        end
      end

      def door(target, url)
        return Endpoints.call_log(url, target[:call]) if target[:call]

        Endpoints.agent_log(url, target.fetch(:agent))
      end
    end
  end
end
