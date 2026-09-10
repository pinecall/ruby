# frozen_string_literal: true

module Pinecall
  # Anything this library refuses to do, and anything the gateway refused to do for it.
  #
  # One root, so an app that wants to catch everything catches `Pinecall::Error` and an app that
  # wants to catch one thing names it. Every message says what was wrong and, where there is one,
  # the move that fixes it — a bare 403 with no sentence in it cost this project two afternoons.
  class Error < StandardError
  end

  # A refusal the gateway sent back as an `error` entry, with the code a program can match on.
  class Refused < Error
    # @return [Hash{Symbol=>Object}] the refusal as the wire wrote it: code, message, and the id.
    attr_reader :refusal

    def initialize(refusal)
      @refusal = refusal
      super("#{refusal[:code]}: #{refusal[:message]}")
    end

    # The gateway's own word for what went wrong, for a `case` that must tell them apart.
    def code = @refusal[:code]
  end

  # A state field was assigned with no tool and no hook running. Tools are the only writers.
  class UnauthoredWrite < Error
    def initialize(field)
      super("state field #{field} was assigned outside a tool and outside a lifecycle hook; " \
            "tools are the only writers of state")
    end
  end

  # A declaration the gateway would refuse, refused here instead — at load, not at the first call.
  class DeclarationRefused < Error
  end

  # A tool said no. The model is waiting for an answer and reads this as the tool's own result.
  class ToolFailed < Error
  end

  # The socket is not up, or it never came up. Not the same as the gateway refusing something.
  class NotConnected < Error
  end
end
