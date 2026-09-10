# frozen_string_literal: true

module Pinecall
  class Client
    # The org's memory as a whole, which today is one verb: the golden `recall` is held to.
    # `client.memory`. What is remembered about ONE contact is `client.memory_of(contact)`, because
    # that door names a contact and this one deliberately does not.
    class Memory
      def initialize(url:, api_key:)
        @url = url
        @api_key = api_key
      end

      # Every question of a golden asked of `recall`. Each question brings the facts of its own
      # contact — `{ holds:, asks:, expects: }` — so no contact of this org is read or written:
      # the gateway writes them to a scratch contact, recalls, and deletes them again. Answers the
      # two figures the ranking is judged by, `recall_at_k` and `ndcg_at_10`, computed by code with
      # no model, and every question it did not answer whole.
      def eval(questions, k: nil)
        asked = { questions: }
        asked[:k] = k unless k.nil?
        body = Protocol::Validate.call!("MemoryGolden", asked, where: "memory golden")
        answer = Rest.post(Endpoints.memory_eval(@url), body, api_key: @api_key)
        Protocol::Validate.call!("MemoryScore", answer, where: "memory score")
      end
    end
  end
end
