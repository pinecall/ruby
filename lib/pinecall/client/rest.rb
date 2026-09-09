# frozen_string_literal: true

module Pinecall
  class Client
    # One JSON request at a REST door: the key at the door, the answer parsed, and a refusal
    # carrying the gateway's own sentence.
    #
    # The socket carries the conversation. These doors carry what is pushed and read outside one —
    # a knowledge base, a contact's memory — and a refusal comes back as `Refused` with the
    # sentence the gateway wrote, because a bare status with no sentence in it cost this project
    # two afternoons.
    module Rest
      module_function

      def get(url, api_key:) = ask(Net::HTTP::Get.new(URI.parse(url)), api_key:)

      def put(url, body, api_key:)
        request = Net::HTTP::Put.new(URI.parse(url))
        request["content-type"] = "application/json"
        request.body = JSON.generate(body)
        ask(request, api_key:)
      end

      def delete(url, api_key:) = ask(Net::HTTP::Delete.new(URI.parse(url)), api_key:)

      # The answer's body as a Hash with symbol keys — nil when it has none — or `Refused`.
      def ask(request, api_key:)
        request["authorization"] = "Bearer #{api_key}"
        request["accept"] = "application/json"
        where = request.uri
        http = Net::HTTP.new(where.host, where.port)
        http.use_ssl = where.scheme == "https"
        answer = http.request(request)
        body = parsed(answer.body)
        return body if answer.is_a?(Net::HTTPSuccess)

        raise Refused.new({ code: answer.code, message: sentence(body, answer) })
      end

      def parsed(text)
        return nil if text.nil? || text.strip.empty?

        JSON.parse(text, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end

      # The gateway's refusals say `detail`; anything else is passed on as it came.
      def sentence(body, answer)
        (body.is_a?(Hash) && (body[:detail] || body[:message])) || answer.body.to_s.strip
      end
    end
  end
end
