# frozen_string_literal: true

module Pinecall
  module CLI
    # `pinecall knowledge push | list | drop`: a folder of Markdown becomes a base the gateway
    # retrieves from, under the name an agent's `docs` declaration says.
    module Knowledge
      # Where an agent keeps the files it answers from, beside `agent.rb`, when nobody said.
      DEFAULT_DIR = "knowledge/docs"

      module_function

      def run(argv, out:, err:)
        verb, *rest = argv
        case verb
        when "push" then push(rest, out:, err:)
        when "list" then list(out:, err:)
        when "drop" then drop(rest.first, out:, err:)
        when nil, "-h", "--help" then usage(out)
        else err.puts("pinecall: knowledge has no verb called #{verb}") || usage(err, status: 2)
        end
      end

      # Every `*.md` under DIR, sent whole to `PUT /v1/knowledge/{base}`. DIR and the base come
      # from the line, or from the `agent.rb` here: its `docs` base (or its slug), and
      # `knowledge/docs` beside it.
      def push(argv, out:, err:)
        dir, base = parse(argv)
        if dir.nil? || base.nil?
          agent = CLI.load_agent(nil, err:)
          return said_what_push_needs(err) if agent.nil?

          base ||= agent.docs&.dig(:base) || agent.slug
          dir ||= File.join(File.dirname(agent.source_file || File.expand_path("agent.rb")), DEFAULT_DIR)
        end
        files = files_under(dir, err:) or return 2
        at_the_gateway(err) do |client|
          pushed = client.knowledge.push(base, files)
          out.puts("#{pushed[:base]} · #{files.size} files · #{pushed[:chunks]} chunks · #{pushed[:took_ms].round} ms")
        end
      end

      def list(out:, err:)
        at_the_gateway(err) do |client|
          bases = client.knowledge.bases
          out.puts("no knowledge base has been pushed to #{client.url}") if bases.empty?
          bases.each do |row|
            out.puts("#{row[:base]} · #{row[:chunks]} chunks · pushed #{day_and_time(row[:pushed_at])}")
          end
        end
      end

      def drop(base, out:, err:)
        return err.puts("pinecall: knowledge drop takes the base to drop") || 2 if base.nil?

        at_the_gateway(err) do |client|
          client.knowledge.drop(base)
          out.puts("#{base} dropped")
        end
      end

      # `[DIR] [--base NAME]`, in either order.
      def parse(argv)
        words = argv.dup
        at = words.index("--base")
        base = at && words.slice!(at, 2)[1]
        dir = words.find { |word| !word.start_with?("-") }
        [dir && File.expand_path(dir), base]
      end

      # Each file as the wire carries it: its path relative to DIR, and its text.
      def files_under(dir, err:)
        return err.puts("pinecall: there is no #{dir}") && nil unless File.directory?(dir)

        found = Dir.glob(File.join(dir, "**", "*.md")).sort
        return err.puts("pinecall: no *.md under #{dir}") && nil if found.empty?

        found.map { |path| { path: path.delete_prefix("#{dir}/"), text: File.read(path) } }
      end

      # The gateway this terminal is pointed at, and the refusal as it wrote it. Exit 1 on one.
      def at_the_gateway(err)
        client = CLI.door(err) or return 2
        yield client
        0
      rescue Refused => e
        err.puts("pinecall: #{e.message}") || 1
      rescue SystemCallError => e
        err.puts("pinecall: #{client.url} did not answer: #{e.message}") || 1
      end

      def said_what_push_needs(err)
        err.puts("  knowledge push takes DIR and --base NAME, or reads both from the agent.rb here")
        2
      end

      def day_and_time(unix) = Time.at(unix).utc.strftime("%Y-%m-%d %H:%M")

      def usage(out, status: 0)
        out.puts(<<~USAGE)
          pinecall knowledge <verb>

            push [DIR] [--base NAME]   every *.md under DIR, sent whole as the base NAME.
                                       DIR is knowledge/docs beside agent.rb and NAME is what
                                       its `docs` says (or its slug) when nobody says otherwise
            list                       every base this org has pushed
            drop BASE                  drop one base
        USAGE
        status
      end
    end
  end
end
