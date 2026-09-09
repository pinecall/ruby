# frozen_string_literal: true

module Pinecall
  class Client
    # What is remembered about one contact: the history, and the right to be forgotten.
    # `client.memory_of(contact)`.
    #
    # A fact is never deleted by a call: a newer one supersedes it and the old one keeps its
    # `invalidated_at`, so the history says what was believed and until when. `forget` is the one
    # verb that removes rows, and it belongs to the contact.
    class ContactMemory
      attr_reader :contact

      def initialize(contact, url:, api_key:)
        @contact = contact
        @url = url
        @api_key = api_key
      end

      # Every fact, current first: `{ id, text, category, source, valid_from, invalidated_at }`.
      def history
        answer = Rest.get(Endpoints.contact_memory(@url, @contact), api_key: @api_key)
        Protocol::Validate.call!("ContactMemory", answer, where: "memory of #{@contact}")[:facts]
      end

      # Forget everything about this contact. Answers how many facts went.
      def forget
        answer = Rest.delete(Endpoints.contact_memory(@url, @contact), api_key: @api_key)
        Protocol::Validate.call!("Forgotten", answer, where: "forget #{@contact}")[:forgotten]
      end
    end
  end
end
