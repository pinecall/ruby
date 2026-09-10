# frozen_string_literal: true

require "io/console"

module Pinecall
  module CLI
    # `pinecall keys add | rm | list`: the provider keys this org brought of its own, read from
    # stdin and printed back never.
    module Keys
      module_function

      def run(argv, input:, out:, err:)
        verb, vendor = argv
        case verb
        when "add" then add(vendor, input:, out:, err:)
        when "rm" then remove(vendor, out:, err:)
        when "list" then list(out:, err:)
        when nil, "-h", "--help" then usage(out)
        else err.puts("pinecall: keys has no verb called #{verb}") || usage(err, status: 2)
        end
      end

      # The key never travels on the command line: argv is visible in `ps` to every user on the
      # box, and a key pasted as an argument is a key in the shell history. On success the vendor
      # is printed and nothing else — the key is echoed nowhere and said in no refusal.
      def add(vendor, input:, out:, err:)
        return err.puts("pinecall: keys add takes the vendor to bring a key for") || 2 if vendor.nil?

        key = a_key(vendor, input:, out:)
        return err.puts("pinecall: no key was given: nothing was brought") || 2 if key.empty?

        Knowledge.at_the_gateway(err) do |client|
          client.provider_keys.add(vendor, key)
          out.puts(vendor)
        end
      end

      def remove(vendor, out:, err:)
        return err.puts("pinecall: keys rm takes the vendor to give back") || 2 if vendor.nil?

        Knowledge.at_the_gateway(err) do |client|
          client.provider_keys.remove(vendor)
          out.puts(vendor)
        end
      end

      def list(out:, err:)
        Knowledge.at_the_gateway(err) do |client|
          vendors = client.provider_keys.vendors
          out.puts("no provider key brought: every call runs on the keys of the box") if vendors.empty?
          vendors.each { |vendor| out.puts(vendor) }
        end
      end

      # Typed with nothing echoed when a person is there, and one piped line when nobody is. A key
      # on the screen is a key in the scrollback, in a screen share and in whatever recorded it.
      def a_key(vendor, input:, out:)
        return input.gets.to_s.chomp unless input.tty?

        out.print("#{vendor} key: ")
        key = input.noecho(&:gets).to_s.chomp
        out.puts
        key
      end

      def usage(out, status: 0)
        out.puts(<<~USAGE)
          pinecall keys <verb>

            add VENDOR    this org's own key for that vendor, read from stdin: typed with nothing
                          echoed on a terminal, one piped line off one. Never from a flag
            rm VENDOR     give that vendor back to the box's own key
            list          the vendors this org brought, by name. Never a key: no door of the
                          runtime answers with one
        USAGE
        status
      end
    end
  end
end
