# frozen_string_literal: true

require "pinecall"
require_relative "lib/agenda"

# Eres la recepción de Clínica Norte. Hablas de usted, con frases cortas.
# Todo lo que dices se lee en voz alta: sin listas, sin markdown, los números como se dicen.
# Nunca inventes una hora: las horas salen de la agenda, siempre.
class ClinicaNorte < Pinecall::Agent
  language :es

  # Voz, modelo, saludo, memoria y conocimiento se configuran en el mundo (`pinecall agent set`,
  # etc.), no aquí: la clase declara idioma, estado, herramientas y vista.

  # La fase decide qué herramientas están visibles.
  stage :identify, :choose, :book, :done

  state :patient, visibility: :pii
  state :slots, []
  # Hora propuesta pendiente del sí, y reserva ya hecha.
  state :proposed
  state :booking
  state(:identified) { !patient.nil? }

  # Vista: views/clinica-norte.erb (ubicación por defecto).

  def on_call(call)
    self.patient = Agenda.por_telefono(call.from.to_s)
    self.stage = :choose if patient
  end

  def on_end(_call)
    log("resultado", { fase: stage, reserva: booking&.dig(:referencia) })
  end

  # Busca al paciente por nombre y teléfono. Pide los dos antes de llamarla.
  # Si no está en la ficha, ofrécele darle de alta.
  tool stage: :identify, pii: %i[name phone]
  def find_patient(name:, phone:)
    self.patient = Agenda.buscar(name, phone)
    self.stage = :choose if patient
    patient
  end

  # Da de alta a un paciente nuevo con su nombre y teléfono.
  # Solo cuando find_patient no lo encontró y él acepta darse de alta.
  tool stage: :identify, pii: %i[name phone]
  def register_patient(name:, phone:)
    self.patient = Agenda.alta(name, phone)
    self.stage = :choose
    patient
  end

  # Horas libres de un día. Un día que nombre el paciente se consulta SIEMPRE,
  # aunque su ficha ya tenga cita ese día.
  tool stage: %i[choose book], preview: 2, params: { day: String }
  def free_slots(day:)
    self.slots = Agenda.libres(day)
    # La hora propuesta era de la lista anterior.
    self.proposed = nil
    self.stage = slots.any? ? :book : :choose
    slots
  end

  # Deja sobre la mesa la hora que el paciente acaba de nombrar. Llámala en cuanto nombre una,
  # antes de leérsela; reservar sigue siendo book, después de su sí.
  tool stage: :book, when: -> { slots.any? }
  def propose(chosen:)
    self.proposed = offered(chosen)
    proposed
  end

  # Reserva la hora que el paciente ya ha confirmado, dicha tal y como se la has leído.
  # Nunca antes de su sí.
  tool stage: :book, when: -> { !proposed.nil? },
       confirm: "Le reservo {{proposed.cuando}} con {{proposed.doctor}}. ¿Lo confirmo?"
  def book(chosen:)
    hueco = offered(chosen)
    # Reservar en la agenda antes de tocar el estado: si el hueco ya se ocupó, el estado no cambia.
    self.booking = Agenda.reservar(patient, hueco)
    self.stage = :done
    booking
  end

  private

  # Resuelve la hora dicha por el modelo contra las horas ofrecidas.
  def offered(chosen)
    dicho = chosen.to_s.downcase
    hueco = slots.find { |uno| dicho.include?(uno.cuando.downcase) || uno.cuando.downcase.include?(dicho) }
    raise Pinecall::ToolFailed, "#{chosen} no es una de las horas que hay sobre la mesa" if hueco.nil?

    hueco
  end
end
