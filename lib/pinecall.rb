# frozen_string_literal: true

# Pinecall's Ruby SDK: write an agent as a class and serve its calls over the gateway socket.
#
# `Pinecall::Agent` and `Pinecall.mount` are the framework; `Pinecall::Client` is the bare socket
# for applications that decide their own answers.

require "json"
require "pinecall/protocol"

require_relative "pinecall/version"
require_relative "pinecall/errors"
require_relative "pinecall/reading"
require_relative "pinecall/view"
require_relative "pinecall/lang"
require_relative "pinecall/blocks"
require_relative "pinecall/agent"
require_relative "pinecall/call_world"
require_relative "pinecall/client"
require_relative "pinecall/bridge"
require_relative "pinecall/ui"
require_relative "pinecall/cli"

module Pinecall
  class << self
    # Mount an agent class on a client; each call gets its own instance. Nothing is sent until
    # `connect`.
    def mount(klass, client:, **options) = Bridge.mount(klass, client:, **options)

    # Render the agent's prompt blocks in send order, offline.
    def render(agent, **context) = Prompt.render(agent, **context)

    # Render the prompt as one page, each block under its header.
    def show_prompt(agent, **context) = Prompt.show(agent, **context)
  end
end
