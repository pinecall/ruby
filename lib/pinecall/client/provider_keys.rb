# frozen_string_literal: true

module Pinecall
  class Client
    # The org's own provider keys (`client.provider_keys`). The org's calls use them from the
    # next call on; other vendors use the platform's keys. The org comes from the API key.
    #
    # Keys are write-only: `vendors` returns names, never values or fingerprints, so no endpoint
    # but the worker's can read a secret back.
    class ProviderKeys
      def initialize(url:, api_key:)
        @url = url
        @api_key = api_key
      end

      # Set the org's key for `vendor`, replacing any previous one. Stored encrypted (Fernet).
      def add(vendor, key)
        Rest.put(Endpoints.provider_key(@url, vendor), { key: }, api_key: @api_key)
        nil
      end

      # Revert `vendor` to the platform key; raises `Refused` if no key was set.
      def remove(vendor)
        Rest.delete(Endpoints.provider_key(@url, vendor), api_key: @api_key)
        nil
      end

      # Vendor names with an org key, sorted.
      def vendors
        answer = Rest.get(Endpoints.provider_keys(@url), api_key: @api_key)
        answer&.fetch(:vendors, nil) || []
      end
    end
  end
end
