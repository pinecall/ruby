# frozen_string_literal: true

module Pinecall
  class Client
    # The knowledge bases of this org, by name: one pushed whole from a folder, all of them
    # listed, one dropped. `client.knowledge`.
    #
    # A push is the tenant's folder as of now: the base is replaced, never merged, so a file that
    # is not in the list is gone from it. The name is what the agent's settings attach.
    class Knowledge
      def initialize(url:, api_key:)
        @url = url
        @api_key = api_key
      end

      # Replace the base with these files, each `{ path:, text: }`. Answers `{ base, chunks,
      # took_ms }`: what it became on the other side, and how long that took.
      def push(base, files)
        body = Protocol::Validate.call!("KnowledgePush", { files: }, where: "knowledge push")
        answer = Rest.put(Endpoints.knowledge(@url, base), body, api_key: @api_key)
        Protocol::Validate.call!("KnowledgePushed", answer, where: "knowledge pushed")
      end

      # Every base this org has pushed: `{ base, chunks, pushed_at }` each.
      def bases
        answer = Rest.get(Endpoints.knowledge_bases(@url), api_key: @api_key)
        Protocol::Validate.call!("KnowledgeList", answer, where: "knowledge list")[:bases]
      end

      # Every question of a golden asked of the base. Answers the two figures the index is judged
      # by — `recall_at_k` and `ndcg_at_10`, computed by code with no model — and every question
      # it missed with what came back instead. A golden is fixed and the index is the variable.
      def eval(base, questions, k: nil)
        asked = { questions: }
        asked[:k] = k unless k.nil?
        body = Protocol::Validate.call!("KnowledgeGolden", asked, where: "knowledge golden")
        answer = Rest.post(Endpoints.knowledge_eval(@url, base), body, api_key: @api_key)
        Protocol::Validate.call!("KnowledgeScore", answer, where: "knowledge score")
      end

      # Drop one base. An agent still naming it retrieves nothing until the next push.
      def drop(base)
        Rest.delete(Endpoints.knowledge(@url, base), api_key: @api_key)
        nil
      end
    end
  end
end
