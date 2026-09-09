# frozen_string_literal: true

require_relative "lib/pinecall/version"

Gem::Specification.new do |spec|
  spec.name = "pinecall"
  spec.version = Pinecall::VERSION
  spec.authors = ["Pinecall"]
  spec.email = ["hello@pinecall.io"]

  spec.summary = "Write a voice agent as a Ruby class: fields are state, tools are verbs, the view is the prompt"
  spec.description = "The application's side of Pinecall. A class whose declared fields are the " \
                     "state, whose `tool` methods are the model's verbs, whose comments are the " \
                     "prompt, and whose ERB view is the part of that prompt which changes. It " \
                     "speaks commands and reads entries over one socket; it never imports the " \
                     "runtime and never sees audio."
  spec.homepage = "https://github.com/pinecall/ruby"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  # `console/` is the compiled React console, vendored the way a Rails engine ships its assets:
  # a browser reads no TypeScript, and installing this gem must not mean installing Node.
  spec.files = Dir["lib/**/*.rb", "sig/**/*.rbs", "exe/*", "console/**/*",
                   "LICENSE", "README.md", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = ["pinecall"]
  spec.require_paths = ["lib"]

  spec.add_dependency "pinecall-protocol"
  # The protocol driver ActionCable runs on: the handshake and the framing, no transport and no
  # event loop, so this gem opens its own socket and owns its own threads.
  spec.add_dependency "websocket-driver", "~> 0.7"
end
