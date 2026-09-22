# frozen_string_literal: true

module Pinecall
  module CLI
    # `pinecall remember [PATHS]`: the goldens `memory.remember` is held to — what a call teaches,
    # and what it must never keep.
    #
    # A case is one call already held, written down for BOTH speakers, so nothing here is re-run:
    # it is handed to the hang-up's one model call exactly as a real call would hand it over. Every
    # answer is judged by code — a category is the policy's own word, a value is a literal, a
    # supersession is an id — because two ways of writing one fact are one fact.
    module Remember
      HELD = "✓"
      BROKEN = "✗"

      # Where the extraction goldens live, beside the agent file. `test/goldens` is the
      # conversation ring and its files are a different shape, so these get a directory of
      # their own rather than a key inside a crowded one.
      DEFAULT_CASES = "test/memory"

      module_function

      def run(argv, out:, err:)
        return usage(out) if ["-h", "--help"].include?(argv.first)

        paths, named, grep = parse(argv)
        agent = CLI.load_agent(named, err:) or return 2
        cases = cases_in(paths, agent, grep, err:) or return 2
        held_to_the_goldens(agent, cases, out:, err:)
      end

      # The class is mounted HERE, exactly as a run mounts it, because the tool names admission
      # refuses a fact for are the class's OWN declaration: the gateway reads it off the socket
      # this process opens. The categories a case may name are the world's memory policy
      # (`pinecall memory policy`). The extraction itself runs there, on
      # the org's model and the org's provider keys and never this terminal's.
      def held_to_the_goldens(agent, cases, out:, err:)
        client = CLI.door(err) or return 2
        # takes_unclaimed: false for the reason a suite has it: this process holds the agent so the
        # run reaches THIS class, and a real call must not ring in a terminal running a suite.
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

      # The run as a person reads it: one line, then the evidence under the cases that did not hold.
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

      # Every case under those paths, or under `test/memory` beside the agent file when nobody
      # narrowed the run. A file holds one case or a list of them, and a case that named itself
      # keeps that name — the file's own basename is what the rest are called, numbered when there
      # are several, so a report names something a person can grep for in their own directory.
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
