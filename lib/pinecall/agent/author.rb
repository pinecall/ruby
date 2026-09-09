# frozen_string_literal: true

module Pinecall
  class Agent
    # Who is writing state right now.
    #
    # This is the whole reason a tool's writes carry its name and nobody else's. It rides Ruby's
    # fiber storage rather than a module-level variable, because one process serves many calls at
    # once: two tools awaiting inside two calls must not read each other's name off a shared stack.
    # `Fiber[]` is per fiber and inherited by the fibers a fiber starts, which is what an async
    # tool needs, and each thread's root fiber has its own — so a thread pool is safe too. The
    # TypeScript side uses AsyncLocalStorage for the same reason and the Python side contextvars.
    module Author
      KEY = :pinecall_author

      module_function

      # The name of whoever is writing state right now, or nil when nobody claimed the write.
      def current
        Fiber[KEY]
      end

      # Run the block with every state write inside it attributed to `name`.
      def with(name)
        held = Fiber[KEY]
        Fiber[KEY] = name
        begin
          yield
        ensure
          Fiber[KEY] = held
        end
      end
    end
  end
end
