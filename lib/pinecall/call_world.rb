# frozen_string_literal: true

module Pinecall
  # One person in the room, as the room's own entries described them.
  Participant = Struct.new(:identity, :kind, :name, :joined_at, :speaking, keyword_init: true)

  # One finished turn of the conversation.
  Turn = Data.define(:who, :text, :speech_id, :interrupted, :at)

  # The call as the class holds it: the line, the room, the conversation, and the six things it
  # may do to any of them.
  #
  # Everything readable here was reduced from entries the client already receives, and every verb
  # is one command on the wire. There is no LiveKit in this file and no escape hatch to it: a need
  # the room cannot express is a new command with a name, not an SDK somebody reaches around it.
  class CallWorld
    # How long `say` waits for the turn it lands as before answering false. A turn that never
    # arrives is a call that already ended, and a tool must not wait on one forever.
    LANDS_WITHIN_S = 30

    attr_reader :id, :contact, :from, :channel, :room, :turns

    # `send` puts one command on the wire for this call. The bridge is what gives it.
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

    # The day the call opened, YYYY-MM-DD in this process's timezone: what a prompt means by today.
    def today = @today ||= Time.now.strftime("%Y-%m-%d")

    # What is running right now, when a write is happening because an outside fact arrived.
    attr_accessor :cause

    # The place of the next outside fact in THIS call's stream of them — not in the wire's.
    def numbered = @events += 1

    # ── the six verbs ────────────────────────────────────────────────────────

    # Say this, word for word, now. True when the turn it lands as arrived, false after 30s.
    def say(text, **options)
      lands { @send.call("agent.say", { text: }.merge(options)) }
    end

    # Make the model speak now, guided by an instruction the caller never hears.
    def reply(instructions, **options)
      lands { @send.call("agent.reply", { instructions: }.merge(options)) }
    end

    # Send a payload to a browser in the room. The log keeps its size, never the payload.
    def send_to(topic, data, to: nil)
      payload = { topic:, data: }
      payload[:to] = Array(to) unless to.nil?
      @send.call("room.send", payload)
    end

    # One participant, by the identity the room knows them as.
    def participant(identity) = Seat.new(identity, @send)

    # A second SIP leg, or a seat for a person.
    def invite(to, kind: nil)
      wanted = { to: }
      wanted[:kind] = kind.to_s unless kind.nil?
      @send.call("room.invite", wanted)
    end

    # Write a line of the app's own into the call's log.
    def log(name, data = {})
      @send.call("call.log", { name: name.to_s, data: data.is_a?(Hash) ? data : { value: data } })
    end

    # End the call from the app's side. `call.ended` follows with reason agent_hung_up.
    def hangup(reason = nil)
      @send.call("call.hangup", reason.nil? ? {} : { reason: })
    end

    # ── what the call learns ─────────────────────────────────────────────────

    # Fold one entry of this call's log into what the class can see.
    def take(type, data, at)
      case type
      when "participant.joined" then joined(data, at)
      when "participant.left" then @room[:participants].reject! { |one| one.identity == data[:identity] }
      when "participant.speaking" then speaking(data)
      when "turn.user" then remember("user", data, at)
      when "turn.agent" then settle(remember("agent", data, at))
      end
    end

    # Everybody in the room right now.
    def participants = @room[:participants].dup

    # The caller's own seat, when there is one.
    def caller_seat = @room[:participants].find { |one| one.kind == "caller" }

    # The last turn either side took.
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

    # Whoever is waiting on a `say` is waiting for the next agent turn: that is what "it landed"
    # means, and there is no id on the wire to match a say to its own turn.
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

    # One participant, and the two things anybody may do to them. Removing the caller ends the call.
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
