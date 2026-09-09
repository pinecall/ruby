# frozen_string_literal: true

# pinecall: the application's side of Pinecall, in Ruby.
#
# A class whose declared fields are the state, whose `tool` methods are the model's verbs, whose
# comments are the prompt, and whose `view` block is the part of that prompt which changes. It
# never imports the runtime, never speaks to a vendor, never sees audio: it sends commands and it
# reads entries, both of them shapes `pinecall-protocol` generated from the one schema.
#
# Two doors out. `Pinecall::Agent` and `Pinecall.mount` are the framework; `Pinecall::Client` is
# the socket alone, for an application that has its own way of deciding what to answer.

require "json"
require "pinecall/protocol"

require_relative "pinecall/version"
require_relative "pinecall/errors"
require_relative "pinecall/reading"
require_relative "pinecall/view"
require_relative "pinecall/lang"
require_relative "pinecall/regions"
require_relative "pinecall/agent"
require_relative "pinecall/call_world"
require_relative "pinecall/client"
require_relative "pinecall/bridge"
require_relative "pinecall/cli"

module Pinecall
  class << self
    # Mount an agent class on a client: it registers once, and from then on every call gets its
    # own instance, its own state and its own rendered prompt. Nothing is sent until `connect`.
    def mount(klass, client:, **options) = Bridge.mount(klass, client:, **options)

    # The prompt this agent would produce right now, region by region. No gateway, no key, no
    # network: this is what `pinecall prompt` prints and what a ring-0 test asserts against.
    def render(agent, **context) = Prompt.render(agent, **context)

    # The same three regions as one page, each under its header.
    def show_prompt(agent, **context) = Prompt.show(agent, **context)
  end
end
