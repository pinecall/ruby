# frozen_string_literal: true

require_relative "cli/env"
require_relative "cli/keys"
require_relative "cli/knowledge"
require_relative "cli/memory"
require_relative "cli/remember"

module Pinecall
  # The `pinecall` command line.
  module CLI
    # Verbs not implemented yet; running one prints its description and exits 0.
    PLANNED = {
      "chat" => "the same agent in this terminal, and a written caller against it",
      "test" => "ring 1: the goldens, through the agent in this process, scored by the gateway",
      "eval" => "ring 3: one real call re-evaluated by the runtime's code checks",
      "login" => "the key typed once — today `pinecall login` is the Node CLI's, and this one reads what it kept"
    }.freeze

    module_function

    # Run one verb and return its exit status.
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
      when "remember" then Remember.run(rest, out:, err:)
      when "keys" then Keys.run(rest, input:, out:, err:)
      when *PLANNED.keys then planned(verb, out)
      else err.puts("pinecall: no verb called #{verb}") || usage(err, status: 2)
      end
    end

    # `pinecall prompt`: print the prompt for the state given by flags, offline.
    def prompt(argv, out:, err:)
      file, options = parse(argv)
      agent = load_agent(file, err:) or return 2
      instance = agent.new.seal
      instance.start_in(options[:state]) unless options[:state].empty?
      out.puts(Pinecall.show_prompt(instance, resumed: options[:resumed]))
      0
    end

    # `pinecall run`: register the agent and serve calls until interrupted.
    def serve(argv, out:, err:)
      file, = parse(argv)
      agent = load_agent(file, err:) or return 2
      client = door(err) or return 2
      mounted = Pinecall.mount(agent, client:)
      client.connect
      out.puts("#{mounted.slug} is answering on #{client.url}")
      sleep
      0
    rescue Interrupt
      client&.close
      0
    end

    # `pinecall whoami`: the gateway and the key's source; never prints the key.
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

    # A client for the configured gateway, or nil with the reason on stderr. Every verb that
    # needs a gateway uses this, so key resolution is uniform.
    def door(err)
      pointed = Env.pointed
      if pointed.api_key.nil?
        no_key(pointed, err)
        return nil
      end
      err.puts("pinecall: #{pointed.notice}") if pointed.notice
      Client.new(url: pointed.url, api_key: pointed.api_key)
    end

    # Load `file` (default `agent.rb`) and return the last agent class it defines.
    def load_agent(file, err:)
      path = File.expand_path(file || "agent.rb")
      return err.puts("pinecall: there is no #{path}") && nil unless File.exist?(path)

      before = Agent.written.dup
      begin
        loaded = require path
      rescue ScriptError, LoadError => e
        return err.puts("pinecall: #{path} did not load: #{e.message}") && nil
      end
      # `require` returns false for an already-loaded file; find its class by source path.
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

    # `--state field=value`: the value is parsed as JSON, or kept as a string.
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
          remember [PATHS]              the goldens memory.remember is held to: what a call teaches
          keys add|rm|list VENDOR       the provider keys this org brought of its own
          version

        Flags for prompt: --stage <name>, --state <field>=<json>, --resumed
        Flags for knowledge push: [DIR] --base <name>
        Planned: #{PLANNED.keys.join(" · ")}
      USAGE
      status
    end
  end
end
