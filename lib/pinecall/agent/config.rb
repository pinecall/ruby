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
    # | `language`          | which of the framework's two word-sets the identity block carries |
    # | `knowledge`         | the `knowledge` block, whole, and the file itself — path and text |
    # | `docs`              | the knowledge base by name, and how its chunks reach the model    |
    # | `memory`            | what memory keeps about a contact across calls, and never keeps   |
    # | `hangup`            | whether the model may end the call itself, and when                |
    module Config
      # The eight that travel as the class wrote them. The other three name a file, a base or a
      # policy, and each is checked at declaration below.
      AS_WRITTEN = %i[phone whatsapp web voice says hears llm language].freeze

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
        # Each one reads with no argument and declares with one, so a subclass can ask what its
        # parent said before deciding to change it.
        AS_WRITTEN.each do |field|
          define_method(field) do |value = NOTHING|
            return config[field] if value.equal?(NOTHING)

            config[field] = value
          end
        end

        # The one file the agent knows by heart, as the path the class wrote. The file is looked
        # for beside the class here, at load, by the rule a view's path follows: a path with
        # nothing behind it is refused with the path, never opened into an empty block at the
        # first call.
        #
        #     knowledge "./knowledge/clinica.md"
        def knowledge(path = NOTHING)
          return config[:knowledge] if path.equal?(NOTHING)

          file = beside_this_file(path.to_s)
          raise DeclarationRefused, "knowledge names a file beside the class, and there is no #{file}" unless File.file?(file)

          @knowledge_file = file
          config[:knowledge] = path.to_s
        end

        # Where the knowledge file is on disk: this class's, or its parent's when it named none.
        def knowledge_file
          @knowledge_file || (superclass.respond_to?(:knowledge_file) ? superclass.knowledge_file : nil)
        end

        # The file's text, read once per process. It is the `knowledge` block and it is half of
        # what `agent.configure` carries, so it is read here and nowhere else — a render happens
        # on every state change, and a file opened per turn is a file opened for nothing.
        def knowledge_text
          return @knowledge_text if defined?(@knowledge_text)

          file = knowledge_file
          @knowledge_text = file && File.read(file)
        end

        # The knowledge base the agent answers from, by the name it was pushed under, and how its
        # chunks reach the model. A path or a glob is refused: a base is pushed first, then named.
        #
        #     docs "clinica-norte"
        #     docs base: "clinica-norte", mode: :retrieved, k: 4, min_score: 0.5
        def docs(base = NOTHING, **options)
          return config[:docs] if base.equal?(NOTHING) && options.empty?

          said = base.equal?(NOTHING) ? options.dup : options.merge(base:)
          said[:base] = said[:base].to_s unless said[:base].nil?
          said[:mode] = said[:mode].to_s unless said[:mode].nil?
          refuse_a_docs_path(said[:base])
          config[:docs] = checked("DocsConfig", said, "docs").freeze
        end

        # What memory keeps about a contact across calls, in the tenant's own words, and what it
        # must never keep. Configuring it is expecting the caller to be remembered.
        #
        #     memory remember: ["alergias", "su médico habitual"], forget: ["pagos"]
        def memory(**policy)
          return config[:memory] if policy.empty?

          said = policy.transform_values { |words| Array(words).map(&:to_s) }
          config[:memory] = checked("MemoryConfig", said, "memory").freeze
        end

        # How the agent opens a call, before the caller has said anything. Exactly one of the two,
        # because there are only two ways to open one: the words themselves, or what the model
        # reads before it finds its own. A class that says nothing here waits for the caller.
        #
        #     greeting "Clínica Norte, buenos días."
        #     greeting reply: "saluda, di que eres la recepción y pregunta en qué puedes ayudar"
        #     greeting say: "Esta llamada será grabada.", allow_interruptions: false
        def greeting(words = NOTHING, **said)
          return config[:greeting] if words.equal?(NOTHING) && said.empty?

          said = said.merge(say: words.to_s) unless words.equal?(NOTHING)
          refuse_unless_one_verb(said)
          config[:greeting] = checked("GreetingConfig", said, "greeting").freeze
        end

        # Whether the model may end the call itself, and when, in your own words. A class that says
        # nothing here cannot hang up: only the caller and a supervisor end a call. The tool is
        # livekit's own `end_call`, and it is hidden while the agent is greeting.
        #
        #     hangup when: "cuando el paciente ya tiene su cita y se despide"
        #
        # `hangup` alone is a declaration too: the model may end the call, in livekit's own words.
        def hangup(**said)
          return config[:hangup] if said.empty? && config.key?(:hangup)

          config[:hangup] = checked("HangupConfig", { when: said[:when].to_s }, "hangup").freeze
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
            prompt: Prompt::FRAMEWORK,
            language: config[:language]&.to_s,
            greeting: config[:greeting],
            voice: voice_config,
            llm: model_config,
            says: pronunciations,
            hears: heard,
            knowledge: knowledge_config,
            docs: config[:docs],
            memory: config[:memory],
            hangup: config[:hangup],
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

        # The file, path and text, sent whole: the same words that are already in the `knowledge`
        # block, so a gateway that keeps a declaration has the file without asking for it.
        def knowledge_config
          text = knowledge_text
          text.nil? ? nil : { path: config[:knowledge], text: }
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

        # One declaration checked the way the gateway would check it, and refused here instead —
        # at load, with the protocol's own sentence.
        def checked(shape, said, where)
          Protocol::Validate.call!(shape, said, where:)
        rescue Protocol::ProtocolError => e
          raise DeclarationRefused, e.message
        end

        # The same rule the runtime holds and the same sentence it refuses with: a greeting names
        # one of the two verbs the wire already has, and a class that named both has not decided.
        def refuse_unless_one_verb(said)
          return if said.key?(:say) ^ said.key?(:reply)

          raise DeclarationRefused,
                "a greeting is one of two things: `say` the words, or `reply` what the model " \
                "reads before it finds its own. " \
                "#{said.key?(:say) ? 'Both were declared' : 'Neither was'} — pick one."
        end

        # A base is a name. A path or a glob is where the files were, which is what `pinecall
        # knowledge push` turns into a name.
        def refuse_a_docs_path(base)
          return unless base.to_s.match?(%r{[*/]})

          raise DeclarationRefused, "docs name the base they were pushed to: " \
                                    "run `pinecall knowledge push ./knowledge/docs --base #{slug}`"
        end

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
