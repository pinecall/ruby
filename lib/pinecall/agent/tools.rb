# frozen_string_literal: true

module Pinecall
  class Agent
    # One declared tool: the half the wire carries, the halves it never sees, and the method.
    Declaration = Data.define(:name, :options, :spec)

    # The tools: which methods are verbs a model may call, and which of them the state shows now.
    #
    # Ruby has no decorators, so `tool` marks the method defined next — the way `sig` does in
    # Sorbet, and the way `private` has always worked. The docstring stays where a reader expects
    # it, above everything, and `Doc` steps over the macro to find it.
    module Tools
      # The macros a class declares its verbs with.
      module Declaring
        # Declare the next method as a tool.
        #
        #     # Reserva la hora que el paciente ya ha confirmado.
        #     tool stage: :book, confirm: "Le reservo el {{chosen}}. ¿Lo confirmo?"
        #     def book(chosen:)
        #
        # @param when [Proc] visibility, and the only one there is: a question asked of the state
        # @param stage [Symbol, Array<Symbol>] sugar for a `when` about the stage field
        # @param confirm [String] the read-back the agent says before running: this is what makes
        #   a tool irreversible on the wire
        # @param preview [Integer] how many rows of a list result the model sees
        # @param pii [Array<Symbol>] parameters that carry personal data, masked in the log
        # @param timeout [Numeric] how long the platform waits for this method, in seconds
        # @param params [Hash{Symbol=>Object}] the type of each parameter, when a bare name is not
        #   enough: `params: { day: String, how_many: Integer }`
        def tool(**options)
          unknown = options.keys - %i[when stage confirm preview pii timeout params doc]
          raise DeclarationRefused, "@tool takes no #{unknown.join(", ")}" unless unknown.empty?

          @pending_tool = options
        end

        # Ruby's own hook for "a method was just defined". It is how `tool` reaches the method
        # under it without a decorator, and it is why the declaration reads top to bottom.
        def method_added(name)
          super
          options = @pending_tool
          return if options.nil?

          @pending_tool = nil
          declare_tool(name, options)
        end

        # Every tool this class declares, its own first, then the ones it inherits.
        def declared_tools
          @declared_tools ||= superclass.respond_to?(:declared_tools) ? superclass.declared_tools.dup : {}
        end

        # One tool by the name a model calls it.
        def tool_named(name) = declared_tools[name.to_sym]

        # Build the declaration and refuse here what the gateway would refuse later.
        def declare_tool(name, options)
          options = Spec.lower(self, name, options)
          spec = Spec.build(self, name, options)
          declared_tools[name.to_sym] = Declaration.new(name: name.to_sym, options:, spec:)
        end
      end

      # ── what an instance does with it ────────────────────────────────────────

      # What this agent is, as the model reads it above everything else.
      def doc = Doc.for_class(self.class)

      # Every tool this agent declares, whether or not the state shows it now.
      def tools = self.class.declared_tools.values.map(&:spec)

      # The tools a model may call right now: the ones whose `when` holds of this state.
      def visible_tools = visible_declarations.map(&:spec)

      # The declarations behind them, for the bridge and for a test that wants the options.
      def visible_declarations
        state = snapshot
        self.class.declared_tools.values.select { |declared| Tools.shows?(declared, state) }
      end

      # Run one tool the way the bridge would: the arguments by name, the writes authored by it.
      def run_tool(name, arguments = {})
        declared = self.class.tool_named(name)
        raise ToolFailed, "#{name}: this agent declares no such tool" if declared.nil?

        Tools.run(self, declared, arguments)
      end

      class << self
        # Whether this state shows this tool. `stage:` was lowered to a `when` at declaration.
        def shows?(declared, state)
          asked = declared.options[:when]
          asked.nil? || ask(asked, state)
        end

        # A `when` is asked of the state, and may be written either way round: `->(s) { s.slots
        # .any? }` takes the reading as an argument, `-> { slots.any? }` reads it as if it were
        # the agent. Both get the same object, so both read the same field by the same name.
        def ask(asked, state)
          reading = state.is_a?(Reading) ? state : Reading.new(state)
          asked.arity.zero? ? reading.instance_exec(&asked) : asked.call(reading)
        end

        # One tool call: the arguments checked against the spec, the method run, the writes inside
        # it carrying its name, and the result cut to the preview the model is allowed to see.
        def run(agent, declared, arguments)
          named = arguments.to_h { |key, value| [key.to_sym, value] }
          refuse_arguments_the_tool_never_asked_for(declared, named)
          result = Author.with(declared.name.to_s) { agent.public_send(declared.name, **named) }
          preview(result, declared.options[:preview])
        end

        # What the MODEL sees of a list result; the state field keeps every row.
        def preview(result, rows)
          return result unless rows.is_a?(Integer) && result.is_a?(Array) && result.size > rows

          result.first(rows)
        end

        def refuse_arguments_the_tool_never_asked_for(declared, named)
          declared_names = (declared.spec[:parameters][:properties] || {}).keys
          unknown = named.keys - declared_names
          return if unknown.empty?

          raise ToolFailed, "#{declared.name}: it takes no #{unknown.join(", ")}"
        end
      end
    end
  end
end
