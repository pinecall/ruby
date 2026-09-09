# frozen_string_literal: true

# The protocol gem lives in the repository beside this one, exactly as `@pinecall/protocol` does
# for the TypeScript package: a path while nothing is published, a version range the day it is.
sibling = File.expand_path("../../protocol/ruby/lib", __dir__)
$LOAD_PATH.unshift(sibling) if File.directory?(sibling)

require "minitest/autorun"
require "pinecall"
require "pinecall/testing"
