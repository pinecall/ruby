# frozen_string_literal: true

module Pinecall
  module CLI
    # `pinecall memory CONTACT` and `pinecall memory forget CONTACT`: what is remembered about
    # one contact, and the right to be forgotten.
    module Memory
      DIM = "\e[2m"
      PLAIN = "\e[0m"

      module_function

      def run(argv, input:, out:, err:)
        verb, contact = argv
        case verb
        when nil, "-h", "--help" then usage(out)
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
        USAGE
        0
      end
    end
  end
end
