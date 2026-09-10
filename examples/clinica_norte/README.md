# Clínica Norte

Un agente entero, escrito como lo escribiría un cliente: la clase, su vista, su agenda de mentira
y su propia suite de ring 0.

```
agent.rb                      la clase: canales, estado, herramientas, hooks
views/clinica-norte.erb       el prompt como función del estado: el bloque `view`
knowledge/clinica.md          lo que el agente sabe de memoria: entero, en el prefijo estático
knowledge/docs/*.md           de lo que responde: se sube con `pinecall knowledge push`, por nombre
lib/agenda.rb                 lo que en producción sería el ERP. No sabe nada de Pinecall
test/clinica_test.rb          ring 0: sin red, sin clave, sin modelo, sin gateway
```

```bash
# el prompt exacto, sin gateway y sin clave
bin/pinecall prompt examples/clinica_norte/agent.rb
bin/pinecall prompt examples/clinica_norte/agent.rb --stage book

# la suite del cliente, como la corre él
ruby -Ilib -I../protocol/ruby/lib examples/clinica_norte/test/clinica_test.rb

# el proceso que se despliega
bin/pinecall run examples/clinica_norte/agent.rb

# la base de conocimiento, subida con el nombre que dice `docs "clinica-norte"`
cd examples/clinica_norte && ../../bin/pinecall knowledge push
```

## Lo que este ejemplo enseña

- **Una fase mueve las herramientas.** `stage :identify, :choose, :book, :done` es un campo del
  estado como cualquier otro, y `stage:` en una tool es azúcar sobre `when:`.
- **`propose` y `book` son dos momentos distintos.** Sin el campo `proposed`, la vista no sabe si
  toca leerle la hora o reservarla, y un modelo obediente vuelve a leérsela en vez de reservar.
- **La hora se resuelve contra las que están sobre la mesa.** El modelo elige diciendo la hora, no
  rellenando una ficha: pedirle un hueco entero termina con la agenda recibiendo uno inventado.
- **`confirm:` es lo que hace `book` irreversible en el cable.** La plataforma lee la frase, oye el
  sí, y sólo entonces corre el método.
- **`preview: 2` corta lo que ve el modelo, no lo que guarda el estado.**
- **Tres cosas que el agente sabe, tres declaraciones.** `knowledge` es un archivo entero en el
  prefijo estático; `docs base: "clinica-norte", k: 4, min_score: 0.5` nombra la base que se subió
  y dice cómo buscarla; `memory` dice con nuestras palabras qué guardar de un paciente entre
  llamadas y qué nunca.
- **La vista es solo lo que escribe la clínica.** Lo que la memoria recuerda y lo que la base
  responde no pasan por el prompt: llegan al modelo como resultado de una herramienta, en el
  historial. La vista pregunta `remembers?("médico habitual")` y decide una frase suya con la
  respuesta; el hecho no se imprime en ningún sitio.
