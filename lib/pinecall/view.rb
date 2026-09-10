# frozen_string_literal: true

require "erb"

module Pinecall
  # The view: a block of the prompt as a template, rendered against the state.
  #
  # It is a view in the sense Rails means: a file of its own, beside the class, mostly prose with
  # holes in it, rendered with the state in scope. `views/clinica-norte.erb` is to this package
  # what `app/views/clinics/show.html.erb` is to a Rails app and what `views/agent.tsx` is to the
  # TypeScript one — the same idea in each language's own material. What it renders to is TEXT,
  # because text is the only thing a model reads.
  #
  #     <%= memory %>
  #
  #     <% if stage == :identify -%>
  #     Saluda y pide nombre y teléfono. Nada más hasta identificar al paciente.
  #     <% end -%>
  #
  #     <% if slots.any? -%>
  #     ## Horas libres
  #
  #     <% slots.each do |slot| -%>
  #     <%= slot[:when] %> con <%= slot[:doctor] %>
  #     <% end -%>
  #     <% end -%>
  #
  # Every state field is in scope by its own name, derived fields included, and so is what
  # surrounds the call: `resumed`, `call[:channel]`, `memory.has?("…")`.
  class View
    # A placeholder the framework writes and never resolves: the gateway reads the line, does the
    # work — open the file, search the memory, retrieve the passages — and replaces it with text.
    # One syntax for all of them, on its own line, so a filler is a line-by-line pass.
    def self.marker(name, payload) = "<!-- #{name}: #{payload} -->"

    # Where a class's view lives when nobody said: `views/<slug>.erb` beside the class's own file,
    # which is the convention this package has instead of a setting. A block of the class's own
    # lives one directory down, under the slug: `views/<slug>/<block>.erb`.
    def self.beside(file, slug, block: nil)
      relative = block ? File.join(slug, "#{block}.erb") : "#{slug}.erb"
      File.join(File.dirname(file), "views", relative)
    end

    # The template in a file. The path is kept, so a failure in the template names the line.
    def self.file(path)
      raise Error, "there is no view at #{path}" unless File.exist?(path)

      new(File.read(path), path)
    end

    # The template written where the class is, for an agent small enough to fit in one file.
    def self.inline(template, called = "(inline view)") = new(template, called)

    attr_reader :path

    def initialize(template, path)
      @path = path
      @erb = ERB.new(template, trim_mode: "-")
      @erb.filename = path
    end

    # Render the view against one reading of the state. Returns the text and the render props it
    # left behind, which is everything one render needs and nothing another one can reach. The
    # blocks of one prompt share one registry, so an id is unique across the whole prompt.
    #
    # `remembers` is what the class said it remembers about a caller: the only words a `memory`
    # tag may ask for by name, and empty for a class that said nothing about it.
    def render(reading, fills: Fills.new, remembers: [])
      context = Context.new(reading, fills, remembers)
      Rendered.new(text: tidy(@erb.result(context.binding_for_the_template)), fills: context.fills)
    end

    # What one render produced: the text of one block, and the blocks its markers point at.
    Rendered = Data.define(:text, :fills)

    # A template is written to be read by a person, so it is indented and spaced for one. What the
    # model reads is the same prose with the ragged edges taken off: no trailing spaces, never
    # more than one blank line in a row, nothing hanging off either end.
    def tidy(text)
      text.lines.map { |line| line.rstrip + "\n" }.join.gsub(/\n{3,}/, "\n\n").strip
    end

    # The render props ONE render left behind, kept under the id its marker carries.
    #
    # A block cannot travel inside a marker, so it stays here and the filler asks for it by id.
    # The registry belongs to the render — in TypeScript that takes an AsyncLocalStorage, because
    # a component is a function anybody may call; here the context IS the render, and two renders
    # in one process cannot see each other's without going looking.
    class Fills
      def initialize
        @kept = {}
      end

      # Keep a block until the gateway comes back with its data; the id goes in the marker.
      def keep(&block)
        id = "fill-#{@kept.size + 1}"
        @kept[id] = block
        id
      end

      # Render one kept block against what the gateway found.
      def fill(id, data)
        block = @kept[id]
        raise Error, "no render prop is kept as #{id}" if block.nil?

        block.call(data).to_s
      end

      def has?(id) = @kept.key?(id)

      def empty? = @kept.empty?
    end

    # What a template is rendered in: the state by name, and the handful of helpers a prompt needs.
    #
    # Everything a template says that is not one of the helpers below is a question about the
    # state, so `stage`, `slots` and `resumed` read as the words they are — the same way an
    # instance variable reads in a Rails view, and refused the same way when nobody set it.
    class Context
      attr_reader :fills

      def initialize(reading, fills, remembers = [])
        @reading = reading
        @fills = fills
        @remembers = remembers
      end

      # ERB needs somewhere to run. This is that place, and its scope is this object.
      def binding_for_the_template = binding

      # What the agent remembers about this caller: a marker the memory service fills at send
      # time. With a block, the block shapes whatever it finds and stays behind under an id.
      # `kinds` asks for some of it, in the words the class remembers, and is refused otherwise.
      def memory(**options, &shape)
        refuse_a_kind_nobody_remembers(options[:kinds])
        placeholder("memory", options, shape)
      end

      # The passages retrieved for this turn: a marker the retriever fills at send time.
      def retrieved(**options, &shape) = placeholder("retrieved", options, shape)

      # The knowledge file this part of the prompt answers from.
      def knowledge(file) = View.marker("knowledge", file.to_s)

      # A marker of the tenant's own, for a filler the tenant runs.
      def marker(name, payload = {}) = View.marker(name.to_s, JSON.generate(payload))

      # A list, one item per line, the way a person would read it out.
      def each_line(items) = Array(items).map { |item| item.to_s.strip }.join("\n")

      # The state as a whole, when a template wants to pass it on rather than ask it something.
      def state = @reading

      def respond_to_missing?(name, include_private = false)
        @reading.respond_to?(name) || super
      end

      def method_missing(name, *args, &block)
        return @reading.public_send(name, *args, &block) if @reading.respond_to?(name)

        super
      end

      private

      # `kinds` asks the memory for some of what it kept, by the CATEGORY each fact was filed
      # under — and a fact is filed under one of the words the class declared with `memory
      # remember:`. A word that is not one of them matches nothing, for ever, and an empty recall
      # reads exactly like a caller nobody has met, so the template looks like it works: a real
      # call filed `cómo prefiere que le llamen` while the view asked for `preference`
      # (2026-09-10). It is a typo, and the render is the only place that sees the tag and the
      # class at once. A class that declares no `remember` keeps whatever the model finds worth
      # keeping and constrains no kind at all.
      def refuse_a_kind_nobody_remembers(kinds)
        return if @remembers.empty? || kinds.nil?

        Array(kinds).each do |kind|
          next if @remembers.include?(kind.to_s)

          raise DeclarationRefused, "memory kinds: #{kind.to_s.inspect} is not one of the words " \
                                    "this class remembers (#{@remembers.join(", ")})"
        end
      end

      def placeholder(name, options, shape)
        payload = options.reject { |_, value| value.nil? }
        payload[:fill] = @fills.keep(&shape) if shape
        View.marker(name, JSON.generate(payload))
      end
    end
  end
end
