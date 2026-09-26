# frozen_string_literal: true

module Pinecall
  class Client
    # Org-wide memory evaluation (`client.memory`): the recall and extraction goldens. For one
    # contact's memory use `client.memory_of(contact)`.
    class Memory
      def initialize(url:, api_key:)
        @url = url
        @api_key = api_key
      end

      # Score `recall` against golden questions, each `{ holds:, asks:, expects: }`. Facts go to
      # a scratch contact that is deleted afterwards; real contacts are untouched.
      #
      # @return [Hash] `recall_at_k`, `ndcg_at_10` (computed without a model) and the misses
      def eval(questions, k: nil)
        asked = { questions: }
        asked[:k] = k unless k.nil?
        body = Protocol::Validate.call!("MemoryGolden", asked, where: "memory golden")
        answer = Rest.post(Endpoints.memory_eval(@url), body, api_key: @api_key)
        Protocol::Validate.call!("MemoryScore", answer, where: "memory score")
      end

      # Run the hang-up extraction on each case (a transcript plus facts already held) with the
      # org's model. `agent` supplies the categories and tool names a case may use.
      #
      # @return [Hash] the model used, the pass count, and kept vs. refused facts per case
      def extraction(agent, cases)
        body = Protocol::Validate.call!("ExtractionCases", { cases: }, where: "extraction cases")
        answer = Rest.post(Endpoints.extraction(@url, agent), body, api_key: @api_key)
        Protocol::Validate.call!("ExtractionRun", answer, where: "extraction run")
      end
    end
  end
end
