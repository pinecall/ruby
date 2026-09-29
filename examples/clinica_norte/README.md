# Clínica Norte

Un agente entero, escrito como lo escribiría un cliente: la clase, su vista, su agenda de mentira
y su propia suite de ring 0.

```
agent.rb                      la clase: idioma, estado, herramientas, hooks
views/clinica-norte.erb       el prompt como función del estado: el bloque `view`
knowledge/docs/*.md           de lo que responde: se sube con `pinecall knowledge push`, por nombre
lib/agenda.rb                 lo que en producción sería el ERP. No sabe nada de Pinecall
test/clinica_test.rb          ring 0: sin red, sin clave, sin modelo, sin gateway
```

```bash
# el prompt exacto, sin gateway y sin clave
bin/pinecall prompt examples/clinica_norte/agent.rb
bin/pinecall prompt examples/clinica_norte/agent.rb --stage book

# la suite del cliente, como la corre él
ruby -Ilib examples/clinica_norte/test/clinica_test.rb

# el proceso que se despliega
bin/pinecall run examples/clinica_norte/agent.rb

# la base de conocimiento, subida con el slug del agente: clinica-norte
cd examples/clinica_norte && ../../bin/pinecall knowledge push
```

Lo que la recepción se sabe de memoria — horarios, precios, qué necesita autorización — no está en
este repo: se escribe en la consola, Settings ▸ Knowledge (o `pinecall agent knowledge edit`), y el
modelo lo lee entero en cada llamada. La voz, el modelo, el saludo, cuándo colgar, las palabras, lo
que la memoria guarda (`pinecall memory policy`) y la base que busca por turno (`pinecall docs
attach clinica-norte --k 4`) son del mundo, no de la clase: se ponen con el CLI de Node
(`pinecall agent set`) o en Settings, y una clase que todavía los declara se rechaza al cargar.

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
- **La clase es el contrato; el mundo, el entorno.** Lo que sabe de memoria, la base que busca y
  lo que recuerda de un paciente entre llamadas son ajustes del agente, por mundo y versionados, y
  no una línea de la clase.
- **La vista es solo lo que escribe la clínica.** Lo que la memoria recuerda y lo que la base
  responde no pasan por el prompt: llegan al modelo como resultado de una herramienta, en el
  historial. La vista pregunta `remembers?("médico habitual")` y decide una frase suya con la
  respuesta; el hecho no se imprime en ningún sitio.
