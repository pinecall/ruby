# frozen_string_literal: true

require_relative "cli/env"
require_relative "cli/knowledge"
require_relative "cli/memory"

module Pinecall
  # `pinecall <verb>`: what a person types, and nothing a program calls.
  #
  # The verbs this package has written, and what each one needs. `prompt` needs no gateway, no key
  # and no network, which is why it is the one a person runs first.
  module CLI
    # The verbs the design names and this tree has not written. Typing one says what it will be
    # and exits 0; a verb leaves this table in the commit that writes it.
    PLANNED = {
      "chat" => "the same agent in this terminal, and a written caller against it",
      "test" => "ring 1: the goldens, through the agent in this process, scored by the gateway",
      "eval" => "ring 3: one real call re-evaluated by the runtime's code checks",
      "login" => "the key typed once — today `pinecall login` is the Node CLI's, and this one reads what it kept"
    }.freeze

    module_function

    # Run one verb. Returns the exit status, so a bin is one line and a test is one call.
    def run(argv, out: $stdout, err: $stderr, input: $stdin)
      verb, *rest = argv
      case verb
      when nil, "-h", "--help", "help" then usage(out)
      when "-v", "--version", "version" then out.puts(VERSION) || 0
      when "prompt" then prompt(rest, out:, err:)
      when "run" then serve(rest, out:, err:)
      when "ui" then UI.run(rest, out:, err:)
      when "whoami" then whoami(out:, err:)
      when "knowledge" then Knowledge.run(rest, out:, err:)
      when "memory" then Memory.run(rest, input:, out:, err:)
      when *PLANNED.keys then planned(verb, out)
      else err.puts("pinecall: no verb called #{verb}") || usage(err, status: 2)
      end
    end

    # The exact prompt this agent would produce, in the state the flags describe. No gateway.
    def prompt(argv, out:, err:)
      file, options = parse(argv)
      agent = load_agent(file, err:) or return 2
      instance = agent.new.seal
      instance.start_in(options[:state]) unless options[:state].empty?
      out.puts(Pinecall.show_prompt(instance, resumed: options[:resumed]))
      0
    end

    # The agent registered and answering: the process you deploy. Binds no port, serves no page.
    def serve(argv, out:, err:)
      file, = parse(argv)
      agent = load_agent(file, err:) or return 2
      client = door(err) or return 2
      mounted = Pinecall.mount(agent, client:)
      client.connect
      out.puts("#{mounted.slug} is answering on #{client.url} (#{mounted.options[:routes].size} routes)")
      sleep
      0
    rescue Interrupt
      client&.close
      0
    end

    # Which gateway, and where this terminal's key came from. It never prints the key itself.
    def whoami(out:, err:)
      pointed = Env.pointed
      out.puts("gateway: #{pointed.url}")
      out.puts("key: #{said(pointed)}")
      err.puts("pinecall: #{pointed.notice}") if pointed.notice
      pointed.api_key.nil? ? 2 : 0
    end

    def said(pointed)
      case pointed.source
      when :environment then "PINECALL_API_KEY"
      when :dev_file then "#{Env.home}/dev — the local gateway's own"
      when :credentials then "#{Env.home}/credentials"
      when :dev_key then "PINECALL_DEV_KEY"
      else "nothing here has one"
      end
    end

    def no_key(pointed, err)
      err.puts("pinecall: no key for #{pointed.url}.")
      err.puts("  export PINECALL_API_KEY=…, or run `pinecall login #{pointed.url}` with the Node CLI once.")
      2
    end

    # The gateway this terminal is pointed at, as a client — or nothing, with the reason on stderr.
    # Every verb that needs a gateway goes through here, so all of them resolve the key one way.
    def door(err)
      pointed = Env.pointed
      if pointed.api_key.nil?
        no_key(pointed, err)
        return nil
      end
      err.puts("pinecall: #{pointed.notice}") if pointed.notice
      Client.new(url: pointed.url, api_key: pointed.api_key)
    end

    # `agent.rb` in this directory when nobody said otherwise, as every example has it.
    def load_agent(file, err:)
      path = File.expand_path(file || "agent.rb")
      return err.puts("pinecall: there is no #{path}") && nil unless File.exist?(path)

      before = Agent.written.dup
      begin
        loaded = require path
      rescue ScriptError, LoadError => e
        return err.puts("pinecall: #{path} did not load: #{e.message}") && nil
      end
      # A file this process already loaded declares nothing new: its class is the one written there.
      written = loaded ? Agent.written - before : Agent.written.select { |klass| klass.source_file == path }
      written = written.select(&:name)
      return err.puts("pinecall: #{path} declares no Pinecall::Agent") && nil if written.empty?

      written.last
    end

    def parse(argv)
      file = argv.first&.start_with?("-") ? nil : argv.first
      options = { state: {}, resumed: false }
      argv.each_with_index do |word, at|
        case word
        when "--state" then options[:state].merge!(as_state(argv[at + 1]))
        when "--stage" then options[:state][:stage] = argv[at + 1].to_sym
        when "--resumed" then options[:resumed] = true
        end
      end
      [file, options]
    end

    # `--state patient='{"name":"Marta"}'` — JSON when it parses as JSON, the word itself when not.
    def as_state(said)
      field, _, value = said.to_s.partition("=")
      { field.to_sym => (JSON.parse(value) rescue value) } # rubocop:disable Style/RescueModifier
    end

    def planned(verb, out)
      out.puts("pinecall #{verb}: #{PLANNED[verb]}")
      out.puts("It is not written in the Ruby package yet.")
      0
    end

    def usage(out, status: 0)
      out.puts(<<~USAGE)
        pinecall <verb>

          prompt [file]                 the exact prompt this agent would produce   (no gateway)
          run [file]                    the agent registered and answering
          ui [agent]                    the console on 127.0.0.1: calls, sessions, evals, and a page to talk
          whoami                        which gateway, and where this key came from
          knowledge push|list|drop      a folder of Markdown as a base the agent retrieves from
          memory [forget] CONTACT       what is remembered about a contact, and forgetting it
          version

        Flags for prompt: --stage <name>, --state <field>=<json>, --resumed
        Flags for knowledge push: [DIR] --base <name>
        Planned: #{PLANNED.keys.join(" · ")}
      USAGE
      status
    end
  end
end
