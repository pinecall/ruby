# frozen_string_literal: true

module Pinecall
  class Agent
    # What configures the agent, as against what it remembers.
    #
    # The TypeScript side keeps a list of eleven field names it must skip on every assignment,
    # because there config and state both live on the instance. Ruby needs no list: config is
    # declared on the CLASS, state on the instance, so "config is not state" is not a rule anybody
    # has to remember — it is where the words are written.
    #
    # | declared            | becomes                                                          |
    # |---------------------|------------------------------------------------------------------|
    # | `phone`, `whatsapp` | a route in agent.register, with that number                        |
    # | `web`               | a route with no number: that is what the widget is                |
    # | `voice`             | a NAME the platform resolves to a vendor and an id, never an id   |
    # | `llm`               | "haiku"/"sonnet"/"opus" lowered to real ids; "provider/model" both |
    # | `says`              | a map written as a map, carried as a list of pronunciations       |
    # | `hears`             | the words the ears must know                                      |
    # | `language`          | which of the framework's two word-sets the static region carries  |
    # | `knowledge`         | a marker in the static region; the gateway opens the file         |
    # | `docs`, `memory`    | read by the view and by the runtime                               |
    module Config
      CONFIG_FIELDS = %i[phone whatsapp web voice says hears llm language knowledge docs memory].freeze

      # The three short names are the family's tiers as the runtime prices them. Anything else is
      # passed through as written: "haiku" on its own is a 404 from Anthropic, and a call that
      # spends its first twenty seconds retrying one is a call nobody hears the agent in.
      SHORT_NAMES = {
        "haiku" => "claude-haiku-4-5-20251001",
        "sonnet" => "claude-sonnet-5",
        "opus" => "claude-opus-5"
      }.freeze

      NOTHING = Object.new.freeze

      # The macros a class configures itself with.
      module Declaring
        # Each of the eleven reads with no argument and declares with one, so a subclass can ask
        # what its parent said before deciding to change it.
        CONFIG_FIELDS.each do |field|
          define_method(field) do |value = NOTHING|
            return config[field] if value.equal?(NOTHING)

            config[field] = value
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

        # Every door this agent answers. The wire has no `channel.add` command — a route is part
        # of agent.register — so the three fields become the declaration here, once, at register.
        #
        # A door is declared by being truthy: `false`, `""` and nothing at all mean "this agent
        # does not answer there", never "answer with an empty number".
        def routes
          %i[phone whatsapp web].filter_map do |channel|
            said = config[channel]
            next if said.nil? || said == false || said == ""

            { channel: channel.to_s, number: said.is_a?(String) ? said : nil }
          end
        end

        # Everything the class says about itself, as the AgentConfig the gateway is sent.
        def wire_config(tools: nil)
          {
            language: config[:language]&.to_s,
            voice: voice_config,
            llm: model_config,
            says: pronunciations,
            hears: heard,
            tools:,
            state_fields: state_field_specs,
            events: event_specs
          }.compact
        end

        # `voice "carolina"` is a name, not an id: sending it as one is how a call spent twenty
        # seconds retrying `voice_id_does_not_exist` while the model apologised. The word travels
        # as the word it is, and the platform resolves it when the declaration lands.
        def voice_config
          said = config[:voice]
          return said if said.is_a?(Hash)
          return nil unless said.is_a?(String) && !said.empty?

          { name: said }
        end

        def model_config
          said = config[:llm]
          return said if said.is_a?(Hash)
          return nil unless said.is_a?(String) && !said.empty?

          provider, model = said.include?("/") ? said.split("/", 2) : ["anthropic", said]
          { provider:, model: SHORT_NAMES.fetch(model, model) }
        end

        # `says DKV: "de ka uve"` is how a person thinks about it; the wire carries a list so the
        # schema can name both halves.
        def pronunciations
          said = config[:says]
          return nil unless said.is_a?(Hash) && !said.empty?

          said.filter_map do |word, spoken|
            { word: word.to_s, spoken: spoken.to_s } if spoken.is_a?(String) && !spoken.empty?
          end
        end

        def heard
          words = Array(config[:hears]).select { |word| word.is_a?(String) && !word.empty? }
          words.empty? ? nil : words
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
