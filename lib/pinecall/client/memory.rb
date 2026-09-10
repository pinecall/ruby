# frozen_string_literal: true

module Pinecall
  class Client
    # The org's memory as a whole, in the two goldens it is held to: the one `recall` answers and
    # the one `memory.remember` answers. `client.memory`. What is remembered about ONE contact is
    # `client.memory_of(contact)`, because that door names a contact and neither of these does.
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

      # The other golden, the write side: a call already written down for both speakers and the
      # facts already held, one hang-up extraction each on the org's own model and keys. The agent
      # is named because its declaration is the vocabulary a case may use — the categories it says
      # it keeps, and the tool names admission refuses a fact for. Answers which model made them,
      # how many held, and every case with what memory would have kept beside what it refused.
      def extraction(agent, cases)
        body = Protocol::Validate.call!("ExtractionCases", { cases: }, where: "extraction cases")
        answer = Rest.post(Endpoints.extraction(@url, agent), body, api_key: @api_key)
        Protocol::Validate.call!("ExtractionRun", answer, where: "extraction run")
      end
    end
  end
end
