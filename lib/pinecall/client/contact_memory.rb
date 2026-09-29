# frozen_string_literal: true

module Pinecall
  class Client
    # Memory about one contact (`client.memory_of(contact)`).
    #
    # Calls never delete facts; a newer fact sets the old one's `invalidated_at`. Only `forget`
    # removes rows.
    class ContactMemory
      attr_reader :contact

      def initialize(contact, url:, api_key:)
        @contact = contact
        @url = url
        @api_key = api_key
      end

      # @return [Array<Hash>] facts, current first:
      #   `{ id, text, category, source, valid_from, invalidated_at }`
      def history
        answer = Rest.get(Endpoints.contact_memory(@url, @contact), api_key: @api_key)
        Wire::Validate.call!("ContactMemory", answer, where: "memory of #{@contact}")[:facts]
      end

      # Delete every fact about the contact.
      #
      # @return [Integer] the number of facts deleted
      def forget
        answer = Rest.delete(Endpoints.contact_memory(@url, @contact), api_key: @api_key)
        Wire::Validate.call!("Forgotten", answer, where: "forget #{@contact}")[:forgotten]
      end
    end
  end
end
