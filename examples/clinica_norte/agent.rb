# frozen_string_literal: true

require "pinecall"
require_relative "lib/agenda"

# Eres la recepción de Clínica Norte. Hablas de usted, con frases cortas.
# Todo lo que dices se lee en voz alta: sin listas, sin markdown, los números como se dicen.
# Nunca inventes una hora: las horas salen de la agenda, siempre.
class ClinicaNorte < Pinecall::Agent
  language :es

  # Y nada más de configuración: la voz, el modelo, el saludo, cuándo colgar, las palabras
  # (`pinecall lexicon`), lo que recuerda (`pinecall memory policy`), lo que se sabe de memoria
  # (Settings ▸ Knowledge) y la base que busca por turno (`pinecall docs push`, `pinecall docs
  # attach`) son del MUNDO — por mundo, por rincón, versionados — y una clase que todavía los
  # declara es rechazada al cargar nombrando el verbo. Tampoco las puertas: un número se apunta a
  # un agente con `pinecall numbers import`. La clase es el contrato: el idioma, el estado, las
  # herramientas y la vista.

  # La fase es un campo del estado como cualquier otro, y es lo único que mueve las herramientas.
  stage :identify, :choose, :book, :done

  state :patient, visibility: :pii
  state :slots, []
  # La hora que está sobre la mesa esperando el sí, y la que ya quedó reservada: son dos momentos
  # distintos de la conversación, y el prompt tiene que poder decir en cuál va.
  state :proposed
  state :booking
  state(:identified) { !patient.nil? }

  # La vista es views/clinica-norte.erb, al lado de este archivo: la convención, así que no hace
  # falta nombrarla. Todo lo que dice lo escribe la clínica y nada más entra ahí.

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
    # Mirar otro día retira lo que hubiera sobre la mesa: la hora propuesta era de la lista
    # anterior y ya no está entre las que se pueden reservar.
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
    # La agenda escribe primero y el estado después: si el hueco se ocupó entre mirar y reservar,
    # el paciente no puede quedarse con una hora suya en el estado ni en el prompt.
    self.booking = Agenda.reservar(patient, hueco)
    self.stage = :done
    booking
  end

  private

  # El modelo elige diciendo la hora, no rellenando una ficha: se resuelve contra las que están
  # sobre la mesa, que es la regla que el prefijo estático dice con palabras.
  def offered(chosen)
    dicho = chosen.to_s.downcase
    hueco = slots.find { |uno| dicho.include?(uno.cuando.downcase) || uno.cuando.downcase.include?(dicho) }
    raise Pinecall::ToolFailed, "#{chosen} no es una de las horas que hay sobre la mesa" if hueco.nil?

    hueco
  end
end
