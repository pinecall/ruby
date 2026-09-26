# frozen_string_literal: true

# Use the sibling protocol checkout until the gem is published.
sibling = File.expand_path("../../protocol/ruby/lib", __dir__)
$LOAD_PATH.unshift(sibling) if File.directory?(sibling)

require "minitest/autorun"
require "pinecall"
require "pinecall/testing"
