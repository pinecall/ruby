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
