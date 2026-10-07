# frozen_string_literal: true

module Pinecall
  class Agent
    # Class-level configuration (state lives on the instance).
    #
    # A class declares its contract: tools, state, view. Runtime settings (voice, models,
    # language, greeting, memory, knowledge) belong to the world and are refused at load with the
    # CLI command that sets them.
    module Config
      # `phone`, `whatsapp` and `web` are accepted for compatibility but ignored. `channel_rules
      # false` leaves the `<channel>` block out of the prompt.
      AS_WRITTEN = %i[phone whatsapp web channel_rules].freeze

      # Settings that moved to the world, and the command that sets each. Must match the
      # TypeScript package's `THE_WORLDS`.
      THE_WORLDS = {
        voice: "pinecall agent set --voice <name>",
        llm: "pinecall agent set --llm <vendor/model>",
        stt: "pinecall agent set --stt <vendor>",
        language: "pinecall agent set --language <tag>",
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

      def self.moved_to_the_world(field)
        "`#{field}` is the world's now, not the class's: #{THE_WORLDS.fetch(field)} — remove it from the class"
      end

      module Declaring
        # Called with no argument, each reads the (possibly inherited) value.
        AS_WRITTEN.each do |field|
          define_method(field) do |value = NOTHING|
            return config[field] if value.equal?(NOTHING)

            config[field] = value
          end
        end

        # World settings raise at load, naming the command that sets them.
        THE_WORLDS.each_key do |field|
          define_method(field) do |*_said, **_options|
            raise DeclarationRefused, Config.moved_to_the_world(field)
          end
        end

        # Set the class docstring explicitly, for classes with no source file.
        def doc(text = NOTHING)
          return Doc.for_class(self) if text.equal?(NOTHING)

          @pinecall_doc = text
        end

        # Accept an external event from `:app` (the application's backend) or `:participant`
        # (a browser). Undeclared events never reach `on_event`.
        def accepts(name, from:)
          declared_events[name.to_s] = Array(from).map(&:to_s)
        end

        def declared_events
          @declared_events ||= superclass.respond_to?(:declared_events) ? superclass.declared_events.dup : {}
        end

        # Declared config, including inherited values.
        def config
          @config ||= superclass.respond_to?(:config) ? superclass.config.dup : {}
        end

        # The slug the class names itself, or nil when it names none.
        def declared_slug = @slug

        # Registration slug; defaults to the class name in kebab-case.
        def slug(name = NOTHING)
          return (@slug || default_slug) if name.equal?(NOTHING)

          @slug = name
        end

        # The AgentConfig sent to the gateway.
        def wire_config(tools: nil)
          {
            prompt: Prompt::FRAMEWORK,
            tools:,
            state_fields: state_field_specs,
            events: event_specs,
            uses_knowledge: (true if Searching.searches?(self))
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
