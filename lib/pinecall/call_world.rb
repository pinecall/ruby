# frozen_string_literal: true

module Pinecall
  # A room participant, as reported by the room's entries.
  Participant = Struct.new(:identity, :kind, :name, :joined_at, :speaking, keyword_init: true)

  # A finished conversation turn.
  Turn = Data.define(:who, :text, :speech_id, :interrupted, :at)

  # The call as an agent sees it: room, turns, and the commands it can send.
  #
  # State is reduced from received entries; each verb is one wire command. No LiveKit access by
  # design: a missing capability should become a new protocol command.
  class CallWorld
    # Seconds `say`/`reply` wait for their turn before returning false (the call may have ended).
    LANDS_WITHIN_S = 30

    attr_reader :id, :contact, :from, :channel, :room, :turns

    # `send` puts one command on the wire for this call; supplied by the bridge.
    def initialize(id:, contact: nil, from: nil, channel: nil, &send)
      @id = id
      @contact = contact
      @from = from
      @channel = channel
      @send = send
      @room = { participants: [], caller: nil }
      @turns = []
      @waiting = []
      @cause = nil
      @events = 0
    end

    # The call's start date, YYYY-MM-DD in the process timezone.
    def today = @today ||= Time.now.strftime("%Y-%m-%d")

    # The external event being handled, if any; logged as the cause of state changes.
    attr_accessor :cause

    # Next per-call event sequence number (not the wire's seq).
    def numbered = @events += 1

    # ── commands ─────────────────────────────────────────────────────────────

    # Speak `text` verbatim now. Returns true once the turn arrives, false after `LANDS_WITHIN_S`.
    def say(text, **options)
      lands { @send.call("agent.say", { text: }.merge(options)) }
    end

    # Make the model speak now, guided by instructions the caller does not hear.
    def reply(instructions, **options)
      lands { @send.call("agent.reply", { instructions: }.merge(options)) }
    end

    # Send a payload to browsers in the room. The log records its size, not its content.
    def send_to(topic, data, to: nil)
      payload = { topic:, data: }
      payload[:to] = Array(to) unless to.nil?
      @send.call("room.send", payload)
    end

    # A participant handle by identity.
    def participant(identity) = Seat.new(identity, @send)

    # Invite a second SIP leg or a person.
    def invite(to, kind: nil)
      wanted = { to: }
      wanted[:kind] = kind.to_s unless kind.nil?
      @send.call("room.invite", wanted)
    end

    # Append an application entry to the call's log.
    def log(name, data = {})
      @send.call("call.log", { name: name.to_s, data: data.is_a?(Hash) ? data : { value: data } })
    end

    # End the call; `call.ended` follows with reason `agent_hung_up`.
    def hangup(reason = nil)
      @send.call("call.hangup", reason.nil? ? {} : { reason: })
    end

    # ── entries ──────────────────────────────────────────────────────────────

    # Apply one log entry to the room and turn state.
    def take(type, data, at)
      case type
      when "participant.joined" then joined(data, at)
      when "participant.left" then @room[:participants].reject! { |one| one.identity == data[:identity] }
      when "participant.speaking" then speaking(data)
      when "turn.user" then remember("user", data, at)
      when "turn.agent" then settle(remember("agent", data, at))
      end
    end

    def participants = @room[:participants].dup

    # The caller's participant, or nil.
    def caller_seat = @room[:participants].find { |one| one.kind == "caller" }

    def last_turn = @turns.last

    private

    def joined(data, at)
      @room[:participants] << Participant.new(
        identity: data[:identity], kind: data[:kind], name: data[:name], joined_at: at, speaking: false
      )
    end

    def speaking(data)
      who = @room[:participants].find { |one| one.identity == data[:identity] }
      who.speaking = data[:speaking] unless who.nil?
    end

    def remember(who, data, at)
      turn = Turn.new(who:, text: data[:text], speech_id: data[:speech_id],
                      interrupted: data[:interrupted] || false, at:)
      @turns << turn
      turn
    end

    # The wire has no id linking a `say` to its turn, so the oldest waiter takes the next agent turn.
    def settle(turn)
      waiting = @waiting.shift
      waiting&.push(turn)
      turn
    end

    def lands
      waiting = Thread::Queue.new
      @waiting << waiting
      yield
      !waiting.pop(timeout: LANDS_WITHIN_S).nil?
    ensure
      @waiting.delete(waiting)
    end

    # A participant handle. Removing the caller ends the call.
    class Seat
      def initialize(identity, send)
        @identity = identity
        @send = send
      end

      def mute(muted: true) = @send.call("participant.mute", { identity: @identity, muted: })

      def remove = @send.call("participant.remove", { identity: @identity })
    end
  end
end
