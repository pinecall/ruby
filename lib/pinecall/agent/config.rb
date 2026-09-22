# frozen_string_literal: true

module Pinecall
  class Agent
    # What configures the agent, as against what it remembers — and what is no longer the class's
    # to say at all.
    #
    # The TypeScript side keeps a list of the field names it must skip on every assignment, because
    # there config and state both live on the instance. Ruby needs no list: config is declared on
    # the CLASS, state on the instance, so "config is not state" is not a rule anybody has to
    # remember — it is where the words are written.
    #
    # A class declares the contract: its tools, its state, its view, its language. Everything it
    # RUNS ON — a voice, the models, an opening, what it remembers, what it reads — is the world's:
    # per world, per corner, versioned, set by the org without a deploy. A class that still says one
    # of those is refused at load, with the verb that sets it now.
    #
    # | declared                   | becomes                                                    |
    # |----------------------------|------------------------------------------------------------|
    # | `language`                 | which of the framework's two word-sets `identity` carries  |
    # | `phone`, `whatsapp`, `web` | nothing: accepted, read by nobody. A door is the org's row |
    module Config
      # The four a class may still write. The doors are kept so an old class still loads; nothing
      # reads them — a number is pointed at an agent by whoever answers the telephone
      # (`pinecall numbers import`), and every agent can be talked to from a page.
      AS_WRITTEN = %i[phone whatsapp web language].freeze

      # The world's fields, and the verb that sets each. The TypeScript package's `THE_WORLDS`,
      # word for word, because it is the same refusal.
      THE_WORLDS = {
        voice: "pinecall agent set --voice <name>",
        llm: "pinecall agent set --llm <vendor/model>",
        stt: "pinecall agent set --stt <vendor>",
        greeting: "pinecall agent set --greeting '…' (or --reply '…')",
        hangup: "pinecall agent set --hangup '…'",
        says: "pinecall lexicon add <word> --say '…'",
        hears: "pinecall lexicon hear <word> …",
        memory: "pinecall memory policy --remember '…' --forget '…'",
        record: "pinecall agent set --record on|off",
        knowledge: "pinecall agent knowledge edit — what the agent knows by heart is a setting, not a file",
        docs: "pinecall docs push, then pinecall docs attach <base>"
      }.freeze

      NOTHING = Object.new.freeze

      # The sentence a class carrying a field of the world's is refused with.
      def self.moved_to_the_world(field)
        "`#{field}` is the world's now, not the class's: #{THE_WORLDS.fetch(field)} — remove it from the class"
      end

      # The macros a class configures itself with.
      module Declaring
        # Each one reads with no argument and declares with one, so a subclass can ask what its
        # parent said before deciding to change it.
        AS_WRITTEN.each do |field|
          define_method(field) do |value = NOTHING|
            return config[field] if value.equal?(NOTHING)

            config[field] = value
          end
        end

        # A field of the world's, written in a class body, is refused right there — at load,
        # before a prompt is printed or a gateway is knocked at — naming the verb that sets it.
        THE_WORLDS.each_key do |field|
          define_method(field) do |*_said, **_options|
            raise DeclarationRefused, Config.moved_to_the_world(field)
          end
        end

        # The class docstring said out loud, for a class with no source file to read it from.
        def doc(text = NOTHING)
          return Doc.for_class(self) if text.equal?(NOTHING)

          @pinecall_doc = text
        end

        # An outside fact this class takes, and from whom — `:app` is the tenant's own backend,
        # `:participant` a browser. A pair nobody declared never reaches the hook.
        def accepts(name, from:)
          declared_events[name.to_s] = Array(from).map(&:to_s)
        end

        def declared_events
          @declared_events ||= superclass.respond_to?(:declared_events) ? superclass.declared_events.dup : {}
        end

        # Everything this class declared about itself, its parent's included.
        def config
          @config ||= superclass.respond_to?(:config) ? superclass.config.dup : {}
        end

        # The slug this agent registers under: what `slug` said, or the class name in kebab-case.
        def slug(name = NOTHING)
          return (@slug || default_slug) if name.equal?(NOTHING)

          @slug = name
        end

        # Everything the class says about itself, as the AgentConfig the gateway is sent: the
        # contract, and nothing of the environment.
        def wire_config(tools: nil)
          {
            prompt: Prompt::FRAMEWORK,
            language: config[:language]&.to_s,
            tools:,
            state_fields: state_field_specs,
            events: event_specs
          }.compact
        end

        def state_field_specs
          declared = state_visibility
          return nil if declared.empty?

          declared.map { |name, visibility| { name: name.to_s, visibility: visibility.to_s } }
        end

        def event_specs
          return nil if declared_events.empty?

          declared_events.map { |name, from| { name:, from: } }
        end

        private

        def default_slug
          (name || "agent").split("::").last
                           .gsub(/([a-z0-9])([A-Z])/, '\1-\2')
                           .gsub(/([A-Z]+)([A-Z][a-z])/, '\1-\2')
                           .downcase
        end
      end
    end
  end
end
