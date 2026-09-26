# frozen_string_literal: true

module Pinecall
  module CLI
    # `pinecall remember [PATHS]`: run the memory extraction goldens.
    #
    # Each case is a full transcript passed to the hang-up extraction as a real call would.
    # Results are checked by code (category names, literal values, superseded ids), not by a model.
    module Remember
      HELD = "✓"
      BROKEN = "✗"

      # Relative to `agent.rb`; separate from `test/goldens`, whose files have another shape.
      DEFAULT_CASES = "test/memory"

      module_function

      def run(argv, out:, err:)
        return usage(out) if ["-h", "--help"].include?(argv.first)

        paths, named, grep = parse(argv)
        agent = CLI.load_agent(named, err:) or return 2
        cases = cases_in(paths, agent, grep, err:) or return 2
        held_to_the_goldens(agent, cases, out:, err:)
      end

      # Mount the class so the gateway reads its tool names from this socket. Categories come
      # from the memory policy; extraction runs on the gateway with the org's model and keys.
      def held_to_the_goldens(agent, cases, out:, err:)
        client = CLI.door(err) or return 2
        # Do not take real calls in a terminal running a suite.
        mounted = Pinecall.mount(agent, client:, takes_unclaimed: false)
        client.connect
        answer = client.memory.extraction(mounted.slug, cases)
        lines_of(answer).each { |line| out.puts(line) }
        answer[:held] == answer[:cases] ? 0 : 1
      rescue Refused => e
        err.puts("pinecall: #{e.message}") || 1
      rescue SystemCallError => e
        err.puts("pinecall: #{client&.url} did not answer: #{e.message}") || 1
      ensure
        client&.close
      end

      # A summary line, then details for failed cases.
      def lines_of(answer)
        counted = "#{answer[:cases]} case#{"s" unless answer[:cases] == 1}"
        first = "#{answer[:agent]} · #{answer[:model]} · #{counted} · " \
                "#{answer[:held]} held · #{answer[:took_ms].round} ms"
        [first, *answer[:results].flat_map { |result| case_lines(result) }]
      end

      def case_lines(result)
        return ["  #{HELD} #{result[:name]}"] if result[:held]

        broke = result[:broke] || []
        width = broke.map { |one| one[:check].length }.max || 0
        ["  #{BROKEN} #{result[:name]}",
         *broke.map { |one| "      #{one[:check].ljust(width)}  #{one[:detail]}" },
         *(result[:wrote] || []).map { |wrote| "      kept      #{wrote}" },
         *(result[:refused] || []).map { |refused| "      refused   #{refused}" }]
      end

      # Load cases from PATHS (default `test/memory`). A file holds one case or an array; unnamed
      # cases take the file's basename, numbered when there are several.
      def cases_in(paths, agent, grep, err:)
        where = paths.empty? ? [beside(agent)] : paths
        found = where.flat_map { |path| files_under(path).flat_map { |file| cases_of(file) } }
        return err.puts("pinecall: #{no_cases(where)}") && nil if found.empty?

        matching = grep.nil? ? found : found.select { |one| one[:name].downcase.include?(grep.downcase) }
        return err.puts("pinecall: no case matched --grep #{grep}") && nil if matching.empty?

        matching
      rescue Refused => e
        err.puts("pinecall: #{e.message}") && nil
      end

      def beside(agent)
        File.join(File.dirname(agent.source_file || File.expand_path("agent.rb")), DEFAULT_CASES)
      end

      def files_under(path)
        return [path] if File.file?(path)

        File.directory?(path) ? Dir.glob(File.join(path, "**", "*.json")).sort : []
      end

      def cases_of(file)
        read = JSON.parse(File.read(file), symbolize_names: true)
        written = read.is_a?(Array) ? read : [read]
        stem = File.basename(file, File.extname(file))
        written.each_with_index.map do |one, index|
          one.merge(name: one[:name] || (written.length > 1 ? "#{stem} ##{index + 1}" : stem))
        end
      rescue JSON::ParserError => e
        raise Refused.new({ code: "unreadable", message: "#{file} is not JSON: #{e.message}" })
      end

      def no_cases(where)
        "no extraction goldens at #{where.join(", ")}: write one, or name the file or directory to run"
      end

      # `[PATHS] [--agent FILE] [--grep TEXT]`, in any order.
      def parse(argv)
        words = argv.dup
        at = words.index("--agent")
        named = at && words.slice!(at, 2)[1]
        at = words.index("--grep")
        grep = at && words.slice!(at, 2)[1]
        [words.reject { |word| word.start_with?("-") }.map { |word| File.expand_path(word) }, named, grep]
      end

      def usage(out)
        out.puts(<<~USAGE)
          pinecall remember [PATHS] [--agent FILE] [--grep TEXT]

            The goldens memory.remember is held to. A case is one call written down for both
            speakers (said), the facts memory already holds (holds), sentences somebody tried to
            plant (plants), and what must come of the hang-up: which categories got a fact
            (expect.writes), which never did (expect.never), which values must not survive in any
            fact's text (expect.never_says), and which held facts the call contradicted
            (expect.invalidates).

            Each case costs ONE model call, the very one a hang-up makes, run in the gateway on
            the org's own keys against the class this terminal is holding. PATHS is test/memory
            beside agent.rb when nobody says otherwise; exit 1 when a case did not hold.
        USAGE
        0
      end
    end
  end
end
