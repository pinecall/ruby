# frozen_string_literal: true

module Pinecall
  class Client
    # Who is listening for what. One registry, used for a whole agent and for a single call alike.
    #
    # A listener that raises is a bug in the app, not a reason to stop reading the socket: it is
    # handed to the error door and the next listener still runs.
    class Listeners
      def initialize(&on_error)
        @by_type = Hash.new { |kept, type| kept[type] = [] }
        @any = []
        @on_error = on_error
        @lock = Mutex.new
      end

      # Listen for one event type. The returned callable stops listening.
      def on(type, &listener)
        @lock.synchronize { @by_type[type.to_s] << listener }
        -> { @lock.synchronize { @by_type[type.to_s].delete(listener) } }
      end

      # Listen for every event, whatever its type.
      def on_any(&listener)
        @lock.synchronize { @any << listener }
        -> { @lock.synchronize { @any.delete(listener) } }
      end

      # Hand one event to everybody waiting for it, then to everybody waiting for anything.
      def emit(event, context)
        for_type, for_any = @lock.synchronize { [@by_type[event.type].dup, @any.dup] }
        for_type.each { |listener| run { listener.call(event.data, context) } }
        for_any.each { |listener| run { listener.call(event, context) } }
      end

      private

      def run
        yield
      rescue StandardError => e
        @on_error.call(e)
      end
    end
  end
end
