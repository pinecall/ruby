# frozen_string_literal: true

module Pinecall
  module CLI
    # `pinecall memory CONTACT`, `pinecall memory forget CONTACT` and `pinecall memory eval`:
    # what is remembered about one contact, the right to be forgotten, and the golden `recall`
    # is held to.
    module Memory
      DIM = "\e[2m"
      PLAIN = "\e[0m"

      # The golden beside the agent that answers with those facts, when nobody says otherwise.
      DEFAULT_GOLDEN = "memory/golden.json"

      module_function

      def run(argv, input:, out:, err:)
        verb, contact = argv
        case verb
        when nil, "-h", "--help" then usage(out)
        when "eval" then evaluate(argv.drop(1), out:, err:)
        when "forget" then forget(contact, input:, out:, err:)
        else history(verb, out:, err:)
        end
      end

      # The history, current first; a fact that was superseded is dimmed and dated.
      def history(contact, out:, err:)
        Knowledge.at_the_gateway(err) do |client|
          facts = client.memory_of(contact).history
          out.puts("nothing is remembered about #{contact}") if facts.empty?
          current, superseded = facts.partition { |fact| fact[:invalidated_at].nil? }
          current.each { |fact| out.puts(line_for(fact)) }
          superseded.each { |fact| out.puts(out.tty? ? "#{DIM}#{line_for(fact)}#{PLAIN}" : line_for(fact)) }
        end
      end

      # Asked once, on a terminal; a script that pipes the answer is not asked.
      def forget(contact, input:, out:, err:)
        return err.puts("pinecall: memory forget takes the contact to forget") || 2 if contact.nil?

        if input.tty?
          out.print("forget everything about #{contact}? [y/N] ")
          return out.puts("kept") || 0 unless input.gets.to_s.strip.downcase.start_with?("y")
        end
        Knowledge.at_the_gateway(err) do |client|
          forgotten = client.memory_of(contact).forget
          out.puts("#{contact}: #{forgotten} facts forgotten")
        end
      end

      # Every question of the golden asked of `recall`, each bringing the facts of its own contact.
      # A golden is run when somebody changed the words a fact is written in, the embedder or a
      # knob — never on a caller's clock. Exit 1 on a question memory did not answer whole, so
      # recall can be held to its golden in CI. The line is the knowledge verbs' own
      # `[GOLDEN] [--k N]`, parsed where it is written once.
      def evaluate(argv, out:, err:)
        file, _base, k = Knowledge.parse(argv, with_k: true)
        if file.nil?
          agent = CLI.load_agent(nil, err:)
          return said_what_eval_needs(err) if agent.nil?

          file = File.join(File.dirname(agent.source_file || File.expand_path("agent.rb")), DEFAULT_GOLDEN)
        end
        questions = Knowledge.golden_at(file, err:) or return 2
        Knowledge.at_the_gateway(err) do |client|
          score = client.memory.eval(questions, k: k)
          out.puts(score_line(score))
          score[:misses].each { |missed| out.puts(miss_line(missed)) }
          return score[:misses].empty? ? 0 : 1
        end
      end

      def said_what_eval_needs(err)
        err.puts("  memory eval takes GOLDEN, or reads memory/golden.json beside the agent.rb here")
        2
      end

      # The two figures on one line, with the embedder that wrote the vectors on both sides of the
      # recall: two scores are comparable only under one model.
      def score_line(score)
        "memory · #{score[:model]} · #{score[:questions]} questions · " \
          "recall@#{score[:k]} #{format("%.2f", score[:recall_at_k])} · " \
          "nDCG@10 #{format("%.2f", score[:ndcg_at_10])} · #{score[:took_ms].round} ms"
      end

      def miss_line(missed)
        "  missed: #{missed[:asks]} → wanted #{missed[:missing].join(", ")}, " \
          "got #{missed[:found].first || "nothing"}"
      end

      # `- the fact  (category · since 2026-09-01)`, or `… · until 2026-09-08` once superseded.
      def line_for(fact)
        since = "since #{day(fact[:valid_from])}"
        until_ = fact[:invalidated_at] && "until #{day(fact[:invalidated_at])}"
        "- #{fact[:text]}  (#{[fact[:category], since, until_].compact.join(" · ")})"
      end

      def day(unix) = Time.at(unix).utc.strftime("%Y-%m-%d")

      def usage(out)
        out.puts(<<~USAGE)
          pinecall memory CONTACT           every fact remembered about a contact, current first
          pinecall memory forget CONTACT    forget all of them. Asks once, on a terminal
          pinecall memory eval [GOLDEN] [--k N]
                                            every question of GOLDEN asked of recall, and
                                            recall@k and nDCG@10 by code with no model. Each
                                            question brings its own facts, so no contact is read
                                            or written. GOLDEN is memory/golden.json beside
                                            agent.rb; exit 1 on a question it did not answer whole
        USAGE
        0
      end
    end
  end
end
