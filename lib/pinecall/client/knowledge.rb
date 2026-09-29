# frozen_string_literal: true

module Pinecall
  class Client
    # The org's knowledge bases (`client.knowledge`). A push replaces the whole base; files not
    # in the push are removed.
    class Knowledge
      def initialize(url:, api_key:)
        @url = url
        @api_key = api_key
      end

      # Replace the base with `files`, each `{ path:, text: }`.
      #
      # @return [Hash] `{ base, chunks, took_ms }`
      def push(base, files)
        body = Wire::Validate.call!("KnowledgePush", { files: }, where: "knowledge push")
        answer = Rest.put(Endpoints.knowledge(@url, base), body, api_key: @api_key)
        Wire::Validate.call!("KnowledgePushed", answer, where: "knowledge pushed")
      end

      # @return [Array<Hash>] `{ base, chunks, pushed_at }` per base
      def bases
        answer = Rest.get(Endpoints.knowledge_bases(@url), api_key: @api_key)
        Wire::Validate.call!("KnowledgeList", answer, where: "knowledge list")[:bases]
      end

      # Score the base against a golden set of questions.
      #
      # @return [Hash] `recall_at_k`, `ndcg_at_10` (computed without a model) and the misses
      def eval(base, questions, k: nil)
        asked = { questions: }
        asked[:k] = k unless k.nil?
        body = Wire::Validate.call!("KnowledgeGolden", asked, where: "knowledge golden")
        answer = Rest.post(Endpoints.knowledge_eval(@url, base), body, api_key: @api_key)
        Wire::Validate.call!("KnowledgeScore", answer, where: "knowledge score")
      end

      # Delete a base. Agents attached to it retrieve nothing until it is pushed again.
      def drop(base)
        Rest.delete(Endpoints.knowledge(@url, base), api_key: @api_key)
        nil
      end
    end
  end
end
