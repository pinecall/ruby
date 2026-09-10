# frozen_string_literal: true

module Pinecall
  class Client
    # One base URL, ten doors. The app configures a host; nothing else writes a path.
    module Endpoints
      module_function

      # `WS /v1/apps`, from whatever base the app gave: http and https are the same host as ws
      # and wss, so a person may write either and neither is wrong.
      def apps(base) = door(base, "/v1/apps", websocket: true)

      # `GET /v1/calls/{id}/events`: one call's log, as a JSON page or as SSE.
      def call_log(base, call) = door(base, "/v1/calls/#{CGI.escape(call)}/events")

      # `GET /v1/agents/{slug}/calls`: the agent's own log — registrations, configurations, errors.
      def agent_log(base, agent) = door(base, "/v1/agents/#{CGI.escape(agent)}/calls")

      # `GET /v1/knowledge`: every base this org has pushed.
      def knowledge_bases(base) = door(base, "/v1/knowledge")

      # `PUT` and `DELETE /v1/knowledge/{base}`: one knowledge base, pushed whole or dropped.
      def knowledge(base, name) = door(base, "/v1/knowledge/#{CGI.escape(name)}")

      def knowledge_eval(base, name) = "#{knowledge(base, name)}/eval"

      # `GET` and `DELETE /v1/contacts/{contact}/memory`: what is remembered about one contact.
      def contact_memory(base, contact) = door(base, "/v1/contacts/#{CGI.escape(contact)}/memory")

      # `POST /v1/contacts/memory/eval`: the golden recall is held to. It names no contact on
      # purpose — every question brings the facts of its own.
      def memory_eval(base) = door(base, "/v1/contacts/memory/eval")

      # `GET /v1/provider-keys`: which vendors this org brought its own key for, by name.
      def provider_keys(base) = door(base, "/v1/provider-keys")

      # `PUT` and `DELETE /v1/provider-keys/{vendor}`: one vendor's key brought, or given back.
      def provider_key(base, vendor) = door(base, "/v1/provider-keys/#{CGI.escape(vendor)}")

      def door(base, path, websocket: false)
        url = URI.parse(base)
        secure = %w[https wss].include?(url.scheme)
        url.scheme = websocket ? (secure ? "wss" : "ws") : (secure ? "https" : "http")
        url.path = "#{url.path.chomp("/")}#{path}"
        url.to_s
      end
    end
  end
end
