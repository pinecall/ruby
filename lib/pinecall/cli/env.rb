# frozen_string_literal: true

module Pinecall
  module CLI
    # Where this terminal is pointed and what opens the door. One resolution order, for every verb.
    #
    # It reads the same two files the TypeScript CLI writes — `~/.pinecall/credentials` and
    # `~/.pinecall/dev` — and writes neither: `pinecall login` belongs to that CLI, and one program
    # keeping a key is enough. A Ruby app on the same laptop therefore finds the same gateway the
    # person already logged in to, without being told twice.
    module Env
      LOCAL = "http://localhost:8080"
      # Every bit outside the owner's. A file that has one of them can be read by somebody else,
      # and a key somebody else can read is not a key we are willing to send anywhere.
      OTHERS = 0o077

      # Where the key came from, so `whoami` can say it and a person can stop guessing.
      Pointed = Data.define(:url, :api_key, :source, :notice)

      module_function

      # The directory both files live in.
      def home = ENV["PINECALL_HOME"] || File.join(Dir.home, ".pinecall")

      # Where this terminal is pointed, and what opens the door there.
      def pointed
        dev = dev_gateway
        url = ENV["PINECALL_URL"] || dev&.dig("url") || the_only_gateway || LOCAL
        return dev_key(url, dev) if dev && same?(url, dev["url"])

        from_the_environment(url) || from_the_credentials(url) || from_a_dev_key(url) ||
          Pointed.new(url:, api_key: nil, source: :nothing, notice: nil)
      end

      # A local gateway on a dev key honours its own key and no other, so an exported
      # PINECALL_API_KEY is ignored HERE — and said out loud, because a bare 403 with no sentence
      # in it cost this project an afternoon twice.
      def dev_key(url, dev)
        notice = if ENV["PINECALL_API_KEY"]
                   "PINECALL_API_KEY is set and ignored: #{url} runs on a dev key and honours its own"
                 end
        Pointed.new(url:, api_key: dev["key"], source: :dev_file, notice:)
      end

      def from_the_environment(url)
        key = ENV.fetch("PINECALL_API_KEY", nil)
        key && Pointed.new(url:, api_key: key, source: :environment, notice: nil)
      end

      def from_the_credentials(url)
        row = credentials.dig("gateways", normalised(url))
        row && Pointed.new(url:, api_key: row["api_key"], source: :credentials, notice: nil)
      end

      def from_a_dev_key(url)
        key = ENV.fetch("PINECALL_DEV_KEY", nil)
        key && Pointed.new(url:, api_key: key, source: :dev_key, notice: nil)
      end

      # The one gateway this person logged in to, when there is exactly one. Two is a choice, and
      # a choice is PINECALL_URL's to make.
      def the_only_gateway
        urls = credentials["gateways"].keys
        urls.size == 1 ? urls.first : nil
      end

      # What a local `pinecall-runtime gateway` on a dev key left behind: where it is and its key.
      def dev_gateway = readable(File.join(home, "dev"))

      def credentials
        read = readable(File.join(home, "credentials")) || {}
        { "api_key" => read["api_key"], "gateways" => read["gateways"].is_a?(Hash) ? read["gateways"] : {} }
      end

      # A missing file, an unreadable one, a broken one and one anybody could read are all nothing.
      def readable(path)
        return nil unless File.exist?(path)
        return nil unless (File.stat(path).mode & OTHERS).zero?

        JSON.parse(File.read(path))
      rescue JSON::ParserError, SystemCallError
        nil
      end

      def normalised(url) = url.to_s.chomp("/")

      def same?(one, other) = normalised(one) == normalised(other)
    end
  end
end
