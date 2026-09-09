# frozen_string_literal: true

require_relative "../pinecall"

module Pinecall
  # A gateway that is not there.
  #
  # Ring 0 is the ring an agent's own suite lives in: no network, no key, no model, no gateway.
  # This is what it mounts against. It answers the two declarations, keeps every command the app
  # sent, and lets the test say what happened next — a call started, the model called a tool, a
  # fact arrived from the tenant's backend — in the words a person would use.
  #
  #     pc = Pinecall::Testing::Gateway.new
  #     Pinecall.mount(ClinicaNorte, client: pc)
  #     call = pc.call_started(from: "+34600123456")
  #     call.tool("find_patient", name: "Marta Ruiz", phone: "+34600123456")
  #     assert_includes call.prompt, "Marta Ruiz"
  module Testing
    # One call the test is driving, and everything the app said during it.
    class Fake
      attr_reader :id, :gateway

      def initialize(gateway, id)
        @gateway = gateway
        @id = id
      end

      # The model calls a tool. Returns the `tool.result` the app sent back.
      def tool(name, **arguments)
        call_id = "tc_#{@gateway.next_seq}"
        @gateway.deliver("tool.call", { call_id:, name: name.to_s, arguments: }, call: @id)
        @gateway.settled { |sent| sent.type == "tool.result" && sent.data[:call_id] == call_id }
      end

      # A fact from the tenant's backend, or from a participant's browser.
      def fact(name, data = {}, from: "app", identity: nil)
        payload = { name: name.to_s, data:, source: from.to_s }
        payload[:identity] = identity unless identity.nil?
        @gateway.deliver("event.received", payload, call: @id)
        @gateway.settle
      end

      # The caller said something.
      def said(text)
        @gateway.deliver("turn.user", { text:, speech_id: "sp_#{@gateway.next_seq}" }, call: @id)
        @gateway.settle
      end

      # The call is over.
      def ended(reason: "caller_hung_up")
        @gateway.deliver("call.ended", { reason:, ended_by: "caller", ended_at: Time.now.to_f, duration_s: 1.0 },
                         call: @id)
        @gateway.settle
      end

      # The dynamic region as the app last sent it: the prompt the model would read now.
      def prompt = last("prompt.set", region: "view")&.dig(:text)

      # The cached prefix as the app last sent it.
      def instructions = last("prompt.set", region: "static")&.dig(:text)

      # The tools the model may call right now, by name.
      def tools = (last("tools.set")&.dig(:tools) || []).map { |spec| spec[:name] }

      # The app's state as it last said it.
      def state = last("state.set")&.dig(:state) || {}

      # Everything said on this call, in order.
      def commands = @gateway.commands.select { |sent| sent.call == @id }

      # The last command of this type, optionally matching some of its fields.
      def last(type, **matching)
        commands.reverse.find do |sent|
          sent.type == type && matching.all? { |field, value| sent.data[field] == value }
        end&.data
      end
    end

    # The gateway itself: what a mounted agent talks to when nothing is listening on a port.
    class Gateway
      attr_reader :commands, :agents

      def initialize
        @commands = []
        @agents = {}
        @seq = 0
        @errors = []
      end

      # What a client says it is. The wire's own field, so a log of a test looks like a log.
      def sdk = "pinecall-ruby-testing/#{VERSION}"

      # The same door `Pinecall::Client` opens, and the reason a mount cannot tell the difference.
      def agent(slug, **options)
        @agents[slug] = Client::Agent.new(slug, options, self)
      end

      # Every command the app has sent, in order.
      def send_command(type:, agent:, call:, data:, id: nil)
        frame = Protocol.command(type:, agent:, call:, data:, id:)
        @commands << frame
        answer(frame)
        frame
      end

      def seen(_event, _call) = nil

      def on_error(error)
        @errors << error
        warn("pinecall testing: #{error.class}: #{error.message}")
      end

      # Anything the app could not hand to anybody, for a test that wants to assert on it.
      attr_reader :errors

      # A call starts. Returns the handle a test drives it with.
      def call_started(id: nil, channel: "web", from: "+34600000000", to: "+34910000000", caller: nil)
        id ||= "CA_#{next_seq}"
        deliver("call.started", { channel:, direction: "inbound", from:, to:, caller:,
                                  started_at: Time.now.to_f }, call: id)
        settle
        Fake.new(self, id)
      end

      # One entry, as the gateway would have written it, handed to whoever is holding the agent.
      def deliver(type, data, call: nil, agent: @agents.keys.first)
        entry = Protocol::Entry.new(seq: next_seq, ts: Time.now.to_f, call:, agent:, type:,
                                    ephemeral: Protocol::Codec.ephemeral?(type), data:)
        @agents[agent]&.take(entry)
        entry
      end

      # Everything a mount does happens on that call's own thread, in order. A test asks for the
      # answer, so it waits for that thread to be idle rather than sleeping and hoping.
      def settle(within_s: 2)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + within_s
        sleep(0.002) while Thread.list.count { |thread| thread.status == "run" } > 1 &&
                           Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        sleep(0.01)
        nil
      end

      # Wait for one command the app has not sent yet, and return its data.
      def settled(within_s: 2)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + within_s
        loop do
          found = @commands.reverse.find { |sent| yield(sent) }
          return found.data unless found.nil?
          raise Error, "the app never sent it" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

          sleep(0.005)
        end
      end

      def next_seq = @seq += 1

      # The two declarations are the only commands the gateway answers; everything else is fire
      # and read the log, exactly as it is against a real one.
      def answer(frame)
        case frame.type
        when "agent.register"
          deliver("agent.registered", { app: "app_test", routes: frame.data[:routes] }, agent: frame.agent)
        when "agent.configure"
          deliver("agent.configured", { changed: frame.data[:config].keys.map(&:to_s) }, agent: frame.agent)
        end
      end
    end
  end
end
