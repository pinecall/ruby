# Clínica Norte

Un agente entero, escrito como lo escribiría un cliente, con el layout del CLI único: el mismo
agente que el ejemplo de TypeScript (`agents/examples/clinica-norte`), con la misma agenda, los
mismos documentos y los mismos once goldens, en Ruby.

```
agents/clinica-norte/agent.rb          la clase: estado, fases, herramientas
agents/clinica-norte/agenda.rb         la agenda de la clínica, inventada y fija: lo que en producción sería su API
agents/clinica-norte/views/clinica-norte.erb   la vista: el bloque `view`, como función del estado
docs/clinica-norte/*.md                de lo que responde por turno: `pinecall docs push` los sube
test/clinica-norte/clinica_test.rb     ring 0: sin red, sin clave, sin modelo, sin gateway
test/clinica-norte/goldens/            ring 1: once conversaciones, más docs.json y memory.json
test/clinica-norte/memory/             los casos de extracción que `pinecall remember` corre
```

La carpeta se llama como el slug del agente: `agents/clinica-norte/` es el agente `clinica-norte`.

```bash
# la suite del cliente, como la corre él
ruby -Ilib examples/clinica_norte/test/clinica-norte/clinica_test.rb

# el resto, con el CLI único (npm i -g pinecall), desde esta carpeta
pinecall prompt --state test/clinica-norte/goldens/no-reserva-antes-del-si.json
pinecall chat
pinecall test                    # ring 1: rake ring1 desde la raíz de la gema
pinecall start
```

El CLI no carga la clase: arranca la entrada `Pinecall::Serve` de esta gema
([../../docs/production.md](../../docs/production.md)). En este checkout la gema es `lib/`:
`RUBYLIB=../../lib` delante de cada verbo, que es lo que `rake ring1` hace.

Lo que la recepción se sabe de memoria — horarios, precios, qué necesita autorización — no está en
este repo: se escribe en la consola, Settings ▸ Knowledge (o `pinecall agent knowledge edit`), y el
modelo lo lee entero en cada llamada. La voz, el modelo, el saludo, el idioma, lo que la memoria
guarda (`pinecall memory policy`) y la base que busca por turno (`pinecall docs attach
clinica-norte --k 4`) son del mundo, no de la clase, y una clase que todavía los declara se
rechaza al cargar.

## Lo que este ejemplo enseña

- **Una fase mueve las herramientas.** `stage :identify, :choose, :book, :done` es un campo del
  estado como cualquier otro, y `stage:` en una tool es azúcar sobre `when:`.
- **Un hueco se reserva por su id, no por su hora.** Dos huecos a la misma hora con distinto
  profesional son indistinguibles en palabras; un id no se parece a otro, y uno que la agenda no
  ofreció se rechaza con la lista de los que sí.
- **`propose` y `book` son dos momentos distintos.** Sin el campo `proposed`, la vista no sabe si
  toca leerle la hora o reservarla, y un modelo obediente vuelve a leérsela en vez de reservar.
- **El día se resuelve a una fecha en el código.** «El martes» dicho un jueves es una fecha y sólo
  una; un día sin agenda vuelve vacío, y la vista lo nombra.
- **`confirm:` es lo que hace `book` irreversible en el cable.** La plataforma lee la frase después
  de la reserva, con lo que la tool devolvió.
- **`preview: 2` corta lo que ve el modelo, no lo que guarda el estado.**
- **La vista es solo lo que escribe la clínica.** Lo que la memoria recuerda y lo que la base
  responde llegan al modelo como resultado de una herramienta, en el historial. La vista pregunta
  `remembers?("médico habitual")` y decide una frase suya con la respuesta.
