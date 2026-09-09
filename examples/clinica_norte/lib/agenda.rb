# frozen_string_literal: true

# La agenda de la clínica, de mentira: lo que en producción sería el ERP del centro.
#
# Está aquí para que el ejemplo se pueda correr sin nada instalado. Lo único que importa de este
# archivo es su forma: métodos que devuelven datos, sin saber nada de Pinecall.
module Agenda
  Paciente = Data.define(:nombre, :telefono, :cita, :doctor)
  Hueco = Data.define(:cuando, :doctor)

  FICHA = {
    "+34600123456" => Paciente.new(nombre: "Marta Ruiz", telefono: "+34600123456",
                                   cita: "jueves a las nueve y media", doctor: "la doctora Vidal")
  }.freeze

  HUECOS = {
    "martes" => [Hueco.new(cuando: "el martes a las diez", doctor: "la doctora Vidal"),
                 Hueco.new(cuando: "el martes a las once y media", doctor: "el doctor Sáez")],
    "miércoles" => [Hueco.new(cuando: "el miércoles a las nueve", doctor: "el doctor Ferrán")]
  }.freeze

  # Una hora que ya está cogida por otro. Se lanza desde la tool y el modelo la lee como respuesta.
  class YaNoEstaLibre < StandardError; end

  module_function

  def por_telefono(telefono) = FICHA[telefono]

  def buscar(nombre, telefono)
    ficha = FICHA[telefono]
    ficha if ficha && ficha.nombre.downcase.include?(nombre.to_s.split.first.to_s.downcase)
  end

  def alta(nombre, telefono) = Paciente.new(nombre:, telefono:, cita: nil, doctor: nil)

  def libres(dia) = HUECOS.fetch(dia.to_s.downcase.strip, [])

  def reservar(paciente, hueco)
    raise YaNoEstaLibre, "#{hueco.cuando} lo acaban de coger" unless libres(hueco.cuando.split[1]).include?(hueco)

    { paciente: paciente.nombre, cuando: hueco.cuando, doctor: hueco.doctor, referencia: "CN-#{rand(1000..9999)}" }
  end
end
