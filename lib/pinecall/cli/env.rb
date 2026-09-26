# frozen_string_literal: true

module Pinecall
  module CLI
    # Resolves the gateway URL and API key for every verb.
    #
    # Reads `~/.pinecall/credentials` and `~/.pinecall/dev`, written by the TypeScript CLI's
    # `pinecall login`; never writes them.
    module Env
      LOCAL = "http://localhost:8080"
      # Group/other permission bits; a key file with any of them set is ignored.
      OTHERS = 0o077

      # The resolved gateway and key, with the key's source for `whoami`.
      Pointed = Data.define(:url, :api_key, :source, :notice)

      module_function

      def home = ENV["PINECALL_HOME"] || File.join(Dir.home, ".pinecall")

      # Resolve the gateway and key.
      def pointed
        dev = dev_gateway
        url = ENV["PINECALL_URL"] || dev&.dig("url") || the_only_gateway || LOCAL
        return dev_key(url, dev) if dev && same?(url, dev["url"])

        from_the_environment(url) || from_the_credentials(url) || from_a_dev_key(url) ||
          Pointed.new(url:, api_key: nil, source: :nothing, notice: nil)
      end

      # A local dev gateway accepts only its own key, so PINECALL_API_KEY is ignored here, with
      # a notice.
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

      # The logged-in gateway when there is exactly one; otherwise PINECALL_URL must choose.
      def the_only_gateway
        urls = credentials["gateways"].keys
        urls.size == 1 ? urls.first : nil
      end

      # URL and key written by a local `pinecall-runtime gateway` running on a dev key.
      def dev_gateway = readable(File.join(home, "dev"))

      def credentials
        read = readable(File.join(home, "credentials")) || {}
        { "api_key" => read["api_key"], "gateways" => read["gateways"].is_a?(Hash) ? read["gateways"] : {} }
      end

      # nil for a missing, unreadable, invalid or group/world-readable file.
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
