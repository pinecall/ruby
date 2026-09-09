# frozen_string_literal: true

module Pinecall
  class Client
    # One base URL, six doors. The app configures a host; nothing else writes a path.
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

      # `GET` and `DELETE /v1/contacts/{contact}/memory`: what is remembered about one contact.
      def contact_memory(base, contact) = door(base, "/v1/contacts/#{CGI.escape(contact)}/memory")

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
