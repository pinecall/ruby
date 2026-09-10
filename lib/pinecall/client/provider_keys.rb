# frozen_string_literal: true

module Pinecall
  class Client
    # The provider keys this org brought of its own: one added, one taken back, the vendors read
    # back by name. `client.provider_keys`.
    #
    # A key added here is the org's own account with that vendor, and every call of this org runs
    # on it from the next one; every vendor nobody brought runs on the box's own key. The org is
    # the key's and is named nowhere: these doors take no org and there is no way to name another.
    #
    # Nothing here reads a key back. `vendors` answers names — never a value, never a prefix,
    # never a fingerprint — because the one door in the runtime that answers with a provider key
    # is the worker's, and a second one would be a way to read a secret out of the platform.
    class ProviderKeys
      def initialize(url:, api_key:)
        @url = url
        @api_key = api_key
      end

      # Keep this org's own key for one vendor, replacing whatever it had for that vendor. The key
      # reaches this method and nothing under it: the row on the other side holds a Fernet token.
      def add(vendor, key)
        Rest.put(Endpoints.provider_key(@url, vendor), { key: }, api_key: @api_key)
        nil
      end

      # Back to the box's own key for that vendor. A vendor this org never brought is `Refused`.
      def remove(vendor)
        Rest.delete(Endpoints.provider_key(@url, vendor), api_key: @api_key)
        nil
      end

      # Which vendors this org brought a key for, by name and in the order a person reads them.
      def vendors
        answer = Rest.get(Endpoints.provider_keys(@url), api_key: @api_key)
        answer&.fetch(:vendors, nil) || []
      end
    end
  end
end
