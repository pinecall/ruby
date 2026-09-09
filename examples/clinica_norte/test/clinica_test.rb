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

    assert_includes call.block("availability"), "el martes a las diez con la doctora Vidal"
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

    assert_includes por_telefono.block("availability"), "Ofrece como máximo dos"

    por_web = @gateway.call_started(id: "CA_web", from: "+34600123456", channel: "web")
    por_web.tool("free_slots", day: "martes")

    assert_includes por_web.block("availability"), "Ofrécele la lista"
  end

  def test_las_horas_son_un_bloque_propio_que_solo_viaja_cuando_cambia_la_lista
    call = @gateway.call_started(from: "+34600123456")

    assert_nil call.block("availability")

    call.tool("free_slots", day: "martes")
    call.tool("propose", chosen: "el martes a las diez")
    enviados = call.commands.count { |sent| sent.type == "prompt.set" && sent.data[:name] == "availability" }

    assert_equal 1, enviados
    assert_includes call.block("availability"), "## Horas libres, en orden"
    refute_includes call.prompt, "Horas libres"
  end

  def test_la_declaracion_lleva_el_archivo_entero_la_base_y_lo_que_la_memoria_guarda
    declared = @mounted.options

    assert_equal "./knowledge/clinica.md", declared[:knowledge][:path]
    assert_includes declared[:knowledge][:text], "calle Mayor 14"
    assert_equal({ base: "clinica-norte" }, declared[:docs])
    assert_includes declared[:memory][:remember], "alergias"
    assert_equal ["pagos"], declared[:memory][:forget]
  end

  def test_los_dos_marcadores_van_en_la_vista_cada_uno_bajo_su_titulo
    call = @gateway.call_started(from: "+34600123456")

    assert_includes call.prompt, %(## Lo que recordamos de este paciente\n<!-- memory: {"kinds":["preference","health"]} -->)
    assert_includes call.prompt, %(## De la base de conocimiento\n<!-- retrieved: {"k":4,"min_score":0.5} -->)
    refute_includes call.block("identity"), "<!-- memory:"
  end

  def test_una_ruta_o_un_glob_no_es_una_base_y_se_rechaza_al_cargar
    refused = assert_raises(Pinecall::DeclarationRefused) do
      Class.new(ClinicaNorte) { docs "./knowledge/docs/**/*.md" }
    end

    assert_includes refused.message, "docs name the base they were pushed to"
    assert_includes refused.message, "pinecall knowledge push ./knowledge/docs --base"
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
