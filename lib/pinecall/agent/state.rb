# frozen_string_literal: true

module Pinecall
  class Agent
    # One field assignment, as the log and the console read it.
    Change = Data.define(:seq, :field, :prev, :next, :author, :at)

    # One named fact the agent put in the call's log.
    LogEntry = Data.define(:seq, :name, :data, :at)

    # The state: what the agent remembers, declared by name, written only by a tool.
    #
    # The TypeScript side hands back a Proxy from its constructor, because there any assignment to
    # any field must be caught. Ruby does not need one: a class says which names are state, and the
    # writer that macro generates IS the recorder. What you cannot do by accident, you cannot do.
    module State
      # The macros a class declares its memory with.
      module Declaring
        # Declare a field of the state, with the value a fresh call starts from.
        #
        #     state :patient, visibility: :pii  # nil until a tool finds one
        #     state :slots, []                  # a list of its own, per call
        #     state(:identified) { !patient.nil? }
        #
        # A block makes the field derived: it is read like any other — a `when` may ask about it,
        # a view may render it — and nothing may assign it, because it is a question about the
        # fields that can be.
        #
        # `visibility:` is who may see the field — `:public`, `:tenant` or `:pii`. A field that
        # says nothing is `tenant`, which is the wire's own default, so the framework never sends
        # a declaration the class did not write.
        def state(name, default = nil, visibility: nil, &derived)
          name = name.to_sym
          refuse_a_name_that_is_taken(name)
          state_visibility[name] = visibility unless visibility.nil?
          if derived
            derived_state[name] = derived
            define_method(name) { instance_exec(&self.class.derived_state[name]) }
            return name
          end
          declared_state[name] = default
          define_method(name) { @state[name] }
          define_method(:"#{name}=") { |value| write_state(name, value) }
          name
        end

        # Declare the stage field and every value it may hold, first one first.
        #
        #     stage :identify, :choose, :book, :done
        #
        # `stage:` on a tool is sugar over `when`, and a stage nobody declared is a tool that would
        # be invisible for the whole call. TypeScript catches that in the compiler; here the class
        # is refused at load, which is the same moment and the same sentence.
        def stage(*names)
          raise DeclarationRefused, "stage names the values the stage may hold; give at least one" if names.empty?

          @stages = names.map(&:to_sym)
          state(:stage, @stages.first)
          @stages
        end

        # Every value this class's stage may hold, its own or its parent's.
        def stages
          @stages || (superclass.respond_to?(:stages) ? superclass.stages : nil)
        end

        # The fields this class declares, with their opening values, its parent's included.
        def declared_state
          @declared_state ||= inherit(:declared_state)
        end

        # The fields that are questions about the others, by name.
        def derived_state
          @derived_state ||= inherit(:derived_state)
        end

        # Who may see which field, for the fields that said.
        def state_visibility
          @state_visibility ||= inherit(:state_visibility)
        end

        # Every name the state answers to, declared or derived.
        def state_names = declared_state.keys + derived_state.keys

        private

        def inherit(what)
          superclass.respond_to?(what) ? superclass.public_send(what).dup : {}
        end

        # Two things by one name is the bug the reader never sees; the class is refused instead.
        def refuse_a_name_that_is_taken(name)
          return unless declared_state.key?(name) || derived_state.key?(name)

          raise DeclarationRefused, "#{self.name || "this agent"} declares #{name} twice"
        end
      end

      # ── what an instance does with it ────────────────────────────────────────

      # Everything the agent remembers right now, copied out so a reader cannot write through it.
      #
      # A derived field is in here beside the declared ones: `identified` is exactly what a `when`
      # asks about, and a view that renders it must not have to know which kind it was.
      def snapshot
        kept = @state.dup
        self.class.derived_state.each_key { |name| kept[name] = public_send(name) }
        kept
      end

      # Put the agent back to a snapshot — the move `on_call` makes when a caller comes back.
      # A whole state: a field the snapshot leaves out is cleared, because that is what it means.
      def restore(state)
        state = state.transform_keys(&:to_sym)
        Author.with(Author.current || "restore") do
          self.class.declared_state.each_key do |name|
            write_state(name, state.key?(name) ? state[name] : nil)
          end
        end
        self
      end

      # Start in the state a case describes: the fields it names, over the ones the agent has.
      # A goldens case says what it is about and nothing else, so `restore` is the wrong door.
      def start_in(state)
        restore(snapshot.merge(state.transform_keys(&:to_sym)))
      end

      # What changed between this snapshot and another, in the order the fields were declared.
      def diff(before, after = snapshot)
        (before.keys | after.keys).filter_map do |field|
          { field:, prev: before[field], next: after[field] } if before[field] != after[field]
        end
      end

      # Drop the change log and keep one sentence in its place. The state itself is untouched:
      # what collapses is the memory of how it got here, which is what a long call runs out of.
      def collapse(summary)
        at = now
        @changes.clear
        @changes << Change.new(seq: next_seq, field: "@summary", prev: nil, next: summary,
                               author: "collapse", at:)
        @changes.last
      end

      # Every change this agent has recorded, oldest first.
      def changes = @changes.dup

      # Hear every field assignment as it happens; the returned callable stops listening.
      def on_change(&listener)
        @change_listeners << listener
        -> { @change_listeners.delete(listener) }
      end

      # Close the declaration and start recording. Everything written before this — the opening
      # values a class gave its fields — is the baseline, not a change.
      def seal
        @sealed = true
        self
      end

      # Whether this agent is recording yet.
      def sealed? = @sealed

      private

      # The one door every state write goes through. Before the seal it is the opening value; after
      # it, it is a change with an author, and there is no way to make one without.
      def write_state(field, value)
        if @sealed
          author = Author.current
          raise UnauthoredWrite, field if author.nil?

          previous = @state[field]
          @state[field] = value
          # An equal value is not a change: re-assigning the same list must not re-render a prompt
          # and must not put a line in the log saying nothing happened.
          return value if previous == value

          record(Change.new(seq: next_seq, field:, prev: previous, next: value, author:, at: now))
        else
          @state[field] = value
        end
        value
      end

      def record(change)
        @changes << change
        @change_listeners.each { |listener| listener.call(change) }
        change
      end

      def next_seq = @seq += 1

      def now = Time.now.to_f
    end
  end
end
