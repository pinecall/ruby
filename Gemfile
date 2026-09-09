# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# A path while nothing is published, a version range the day it is — the same arrangement the
# TypeScript package has with ../protocol/typescript.
gem "pinecall-protocol", path: "../protocol/ruby"

group :development, :test do
  gem "minitest", "~> 5.16"
  gem "rake", "~> 13.0"
  gem "rbs", "~> 3.0"
end
