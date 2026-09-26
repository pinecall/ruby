# frozen_string_literal: true

module Pinecall
  # The framework's standing rules and protocols, per language. Constant, so they live in the
  # cached identity block.
  module Lang
    WORDS = {
      "es" => {
        rules: [
          "- No inventes ningún dato: lo que no salga de una herramienta o del conocimiento, no lo digas.",
          "- Una sola pregunta por turno, y espera la respuesta.",
          "- Habla como una persona al teléfono: frases cortas, sin listas ni markdown."
        ].join("\n"),
        protocols: [
          "- Para actuar usa una herramienta; decir que has hecho algo no lo hace.",
          "- Antes de una acción irreversible lee en voz alta lo que vas a hacer y espera un sí explícito.",
          "- Si no puedes resolverlo, dilo y ofrece pasar con una persona."
        ].join("\n")
      }.freeze,
      "en" => {
        rules: [
          "- Invent nothing: if it did not come from a tool or from the knowledge, do not say it.",
          "- One question per turn, and wait for the answer.",
          "- Talk like a person on the phone: short sentences, no lists, no markdown."
        ].join("\n"),
        protocols: [
          "- To act, call a tool; saying you have done something does not do it.",
          "- Before an irreversible action read back what you are about to do and wait for an explicit yes.",
          "- If you cannot solve it, say so and offer to hand over to a person."
        ].join("\n")
      }.freeze
    }.freeze

    DEFAULT = "es"

    module_function

    # Words for the class's language; unknown languages fall back to the default.
    def words_for(klass)
      said = klass.respond_to?(:language) ? klass.language : nil
      code = (said || DEFAULT).to_s.downcase.split(/[-_]/).first
      WORDS[code] || WORDS[DEFAULT]
    end

    def languages = WORDS.keys
  end
end
