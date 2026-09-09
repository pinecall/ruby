# frozen_string_literal: true

module Pinecall
  # The state as something you can ask questions of by name.
  #
  # A snapshot is a plain Hash — that is what goes on the wire and what a test compares — but the
  # two places a person writes a question about it, a tool's `when:` and a view, read far better
  # as sentences. So both are handed this: `s.slots.any?` and `s[:slots].any?` are the same
  # question, and a field nobody declared raises instead of quietly being nil.
  class Reading
    def initialize(state)
      @state = state
    end

    # The state as the Hash it is: what the wire carries and what a golden compares against.
    def to_h = @state

    def [](name) = @state[name.to_sym]

    def key?(name) = @state.key?(name.to_sym)

    def fetch(name, *rest) = @state.fetch(name.to_sym, *rest)

    def respond_to_missing?(name, include_private = false)
      @state.key?(name) || super
    end

    def method_missing(name, *args)
      return @state[name] if args.empty? && @state.key?(name)

      super
    end

    def inspect = "#<Pinecall::Reading #{@state.inspect}>"
  end
end

module Pinecall
  # What a static block is rendered against: a state that refuses every question, by name.
  #
  # A static block is sent once per call and cached by the provider, so a block that reads a
  # field is a block whose text would move — the one thing the region promises it never does.
  # The refusal names the template and the field, at render, which is where a person can see it.
  class StaticReading
    # Ruby probes an object for `to_ary`, `to_str` and their kind before treating it as one; those
    # are not questions about the state and are answered the ordinary way.
    A_CONVERSION = /\Ato_/

    def initialize(template)
      @template = template
    end

    def to_h = refuse("the state")

    def [](name) = refuse(name)

    def key?(name) = refuse(name)

    def fetch(name, *) = refuse(name)

    def respond_to_missing?(name, _include_private = false) = !name.to_s.match?(A_CONVERSION)

    def method_missing(name, *)
      respond_to_missing?(name) ? refuse(name) : super
    end

    def inspect = "#<Pinecall::StaticReading #{@template}>"

    private

    def refuse(field) = raise(StaticBlockReadsState.new(@template, field))
  end
end
