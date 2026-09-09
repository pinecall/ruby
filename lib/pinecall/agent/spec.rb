# frozen_string_literal: true

module Pinecall
  class Agent
    # One tool, as the gateway receives it. The declaration is refused here or nowhere.
    #
    # A model reads the docstring and fills a JSON object by NAME, so a tool takes keyword
    # arguments and nothing else: positional ones would be filled by position, which is a thing
    # only a human can get right. The parameter names come from the method itself — Ruby keeps
    # them — and their types from `params:`, because a Ruby signature carries none.
    module Spec
      A_NAME_A_MODEL_CAN_CALL = /\A[A-Za-z][A-Za-z0-9_]*\z/

      # What a bare name means when nobody said otherwise. A model filling a slot in a phone
      # conversation is writing words; anything that is not text says so in `params:`.
      TEXT = { type: "string" }.freeze

      class << self
        # `stage: :book` is sugar over `when`, lowered here, at declaration time, so that from
        # here on there is one kind of visibility and the framework asks it one way.
        def lower(klass, name, options)
          wanted = options[:stage]
          return options if wanted.nil?

          wanted = Array(wanted).map(&:to_sym)
          refuse_a_stage_the_class_does_not_declare(klass, name, wanted)
          asked = options[:when]
          in_stage = ->(state) { wanted.include?(state[:stage]) && (asked.nil? || Tools.ask(asked, state)) }
          options.merge(when: in_stage)
        end

        # Build the wire spec for one declared method, refusing what the gateway would refuse.
        def build(klass, name, options)
          refuse_a_name_no_model_can_call(name)
          method = klass.instance_method(name)
          spec = {
            name: name.to_s,
            description: description!(klass, name, options),
            parameters: parameters(method, options[:params] || {}),
            side_effect: options[:confirm] ? "irreversible" : "read"
          }
          spec[:confirm] = options[:confirm] if options[:confirm]
          spec[:pii] = pii!(options, spec) if options[:pii]
          spec[:timeout_s] = options[:timeout].to_f if options[:timeout]
          Protocol::Validate.call!("ToolSpec", spec, where: "tool #{name}")
          spec.freeze
        end

        # The JSON Schema a model must satisfy: the method's own keyword names, and their types.
        def parameters(method, declared)
          properties = {}
          required = []
          method.parameters.each do |kind, called|
            next if kind == :block

            refuse_an_argument_a_model_cannot_fill(method, kind, called)
            properties[called] = schema_of(declared[called])
            required << called.to_s if kind == :keyreq
          end
          { type: "object", properties:, required:, additionalProperties: false }
        end

        # `params: { day: String, how_many: Integer, slot: { type: "object" } }` — a class, a list
        # holding one class, or the JSON Schema written out when the shape is worth saying.
        def schema_of(declared)
          case declared
          when nil then TEXT
          when Hash then declared
          when Array then { type: "array", items: schema_of(declared.first) }
          when Class then of_class(declared)
          else TEXT
          end
        end

        def of_class(klass)
          case klass.name
          when "Integer" then { type: "integer" }
          when "Float", "Numeric" then { type: "number" }
          when "TrueClass", "FalseClass" then { type: "boolean" }
          when "Array" then { type: "array", items: TEXT }
          when "Hash" then { type: "object", additionalProperties: true }
          else TEXT
          end
        end

        # ── what a declaration is refused for ──────────────────────────────────

        def description!(klass, name, options)
          said = options[:doc] || Doc.for_method(klass, name)
          return said unless said.nil? || said.empty?

          raise DeclarationRefused,
                "tool #{name}: without a docstring no model can choose it; write a `# one line` " \
                "comment above it, or pass doc: \"…\" for a class with no source to read"
        end

        def pii!(options, spec)
          wanted = Array(options[:pii]).map(&:to_sym)
          unknown = wanted - spec[:parameters][:properties].keys
          return wanted.map(&:to_s) if unknown.empty?

          raise DeclarationRefused,
                "tool #{spec[:name]}: pii names parameters the tool has; unknown: #{unknown.join(", ")}"
        end

        def refuse_a_name_no_model_can_call(name)
          return if A_NAME_A_MODEL_CAN_CALL.match?(name.to_s)

          raise DeclarationRefused, "a tool name is one word a model can call, not #{name}"
        end

        def refuse_an_argument_a_model_cannot_fill(method, kind, called)
          return if %i[key keyreq].include?(kind)

          raise DeclarationRefused,
                "tool #{method.name}: a model fills a JSON object by name, so a tool takes " \
                "keyword arguments; #{called || kind} is not one"
        end

        def refuse_a_stage_the_class_does_not_declare(klass, name, wanted)
          declared = klass.stages
          if declared.nil?
            raise DeclarationRefused,
                  "tool #{name}: stage names a value of this agent's own stage field, and " \
                  "#{klass.name || "this class"} declares none; add `stage :identify, :book` to " \
                  "the class, or ask `when:` instead"
          end
          unknown = wanted - declared
          return if unknown.empty?

          raise DeclarationRefused,
                "tool #{name}: #{unknown.join(", ")} is not one of this agent's stages " \
                "(#{declared.join(", ")})"
        end
      end
    end
  end
end
