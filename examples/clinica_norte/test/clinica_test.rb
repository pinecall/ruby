# frozen_string_literal: true

# Ring 0: la clase, en este proceso, sin red, sin clave, sin modelo y sin gateway.
#
# Es la suite que un cliente escribe en SU repo. Lo único que hace falta es `pinecall/testing`.
require "minitest/autorun"
require "pinecall"
require "pinecall/testing"
require_relative "../agent"

class ClinicaTest < Minitest::Test
  def setup
    @gateway = Pinecall::Testing::Gateway.new
    @mounted = Pinecall.mount(ClinicaNorte, client: @gateway)
  end

  def test_una_paciente_de_la_ficha_no_tiene_que_decir_su_nombre_otra_vez
    call = @gateway.call_started(from: "+34600123456")

    assert_includes call.prompt, "Hablas con Marta Ruiz"
    assert_includes call.prompt, "no vuelvas a pedirle el nombre"
    assert_equal %w[free_slots], call.tools
  end

  def test_un_numero_desconocido_empieza_por_identificar
    call = @gateway.call_started(from: "+34999888777")

    assert_includes call.prompt, "Saluda y pide nombre y teléfono."
    assert_equal %w[find_patient register_patient], call.tools
  end

  def test_mirar_un_dia_pone_las_horas_en_el_prompt_y_abre_reservar
    call = @gateway.call_started(from: "+34600123456")
    call.tool("free_slots", day: "martes")

    assert_includes call.prompt, "el martes a las diez con la doctora Vidal"
    assert_includes call.tools, "propose"
  end

  def test_el_modelo_solo_ve_dos_horas_aunque_el_estado_guarde_todas
    call = @gateway.call_started(from: "+34600123456")
    visto = call.tool("free_slots", day: "martes")[:output]

    assert_equal 2, visto.size
    assert_equal 2, @mounted.serving(call.id).slots.size
  end

  def test_una_hora_que_nadie_ofrecio_se_rechaza_en_vez_de_reservarse
    call = @gateway.call_started(from: "+34600123456")
    call.tool("free_slots", day: "martes")
    refusal = call.tool("propose", chosen: "el domingo a las tres")

    assert_includes refusal[:error], "no es una de las horas"
  end

  def test_reservar_es_irreversible_y_por_eso_lleva_una_lectura_en_voz_alta
    spec = @mounted.options[:tools].find { |one| one[:name] == "book" }

    assert_equal "irreversible", spec[:side_effect]
    assert_includes spec[:confirm], "¿Lo confirmo?"
  end

  def test_el_telefono_pide_ofrecer_dos_horas_y_la_web_la_lista
    por_telefono = @gateway.call_started(id: "CA_tel", from: "+34600123456", channel: "phone")
    por_telefono.tool("free_slots", day: "martes")

    assert_includes por_telefono.prompt, "Ofrece como máximo dos"

    por_web = @gateway.call_started(id: "CA_web", from: "+34600123456", channel: "web")
    por_web.tool("free_slots", day: "martes")

    assert_includes por_web.prompt, "Ofrécele la lista"
  end

  def test_solo_la_vista_se_reenvia_cuando_se_mueve_el_estado
    call = @gateway.call_started(from: "+34600123456")
    call.tool("free_slots", day: "martes")
    enviados = call.commands.select { |sent| sent.type == "prompt.set" }.map { |sent| sent.data[:name] }

    assert_equal 1, enviados.count("identity")
    assert_equal 0, enviados.count("knowledge")
    assert_operator enviados.count("view"), :>, 1
  end

  # La voz, el modelo, el saludo, lo que sabe y lo que recuerda son del mundo: la declaración lleva
  # el contrato y nada más.
  def test_la_declaracion_es_el_contrato_y_nada_del_mundo
    declared = @mounted.options

    assert_equal "es", declared[:language]
    %i[voice llm greeting hangup says hears knowledge docs memory routes].each do |field|
      refute declared.key?(field), "la declaración no lleva #{field}"
    end
  end

  # Lo que la memoria y la base devuelven llega como resultado de una herramienta, en el
  # historial. Por el prompt no pasa: ni un hecho, ni un trozo, ni una línea del framework.
  def test_la_vista_es_solo_lo_que_escribe_la_clinica
    call = @gateway.call_started(from: "+34600123456")

    refute_includes call.prompt, "<!--"
  end

  # Lo que ya sabemos del paciente decide una frase nuestra; el hecho en sí no se imprime.
  def test_lo_que_ya_sabemos_del_paciente_decide_una_frase_pero_no_se_lee_en_la_vista
    call = @gateway.call_started(from: "+34600123456")
    vista = Pinecall.render(@mounted.serving(call.id),
                            remembered: ["su médico habitual: la doctora Vidal"])[:view]

    assert_includes vista, "Ofrece primero las horas de su médico habitual."
    refute_includes vista, "su médico habitual: la doctora Vidal"
  end

  def test_una_clase_que_todavia_declara_la_voz_se_rechaza_al_cargar_con_el_verbo
    refused = assert_raises(Pinecall::DeclarationRefused) do
      Class.new(ClinicaNorte) { voice "carolina" }
    end

    assert_includes refused.message, "pinecall agent set --voice <name>"
  end

  def test_al_reservar_el_prompt_deja_de_pedir_nada_y_se_despide
    call = @gateway.call_started(from: "+34600123456")
    call.tool("free_slots", day: "martes")
    call.tool("propose", chosen: "el martes a las diez")
    call.tool("book", chosen: "el martes a las diez")

    assert_includes call.prompt, "Ya está reservada"
    assert_includes call.prompt, "Despídete"
    assert_empty call.tools
  end
end
