# frozen_string_literal: true

require "erb"

module Pinecall
  # The view: the dynamic region of the prompt as a template, rendered against the instance.
  #
  # It is a view in the sense Rails means: a file of its own, beside the class, mostly prose with
  # holes in it, rendered with the state in scope. `views/clinica-norte.erb` is to this package
  # what `app/views/clinics/show.html.erb` is to a Rails app — the object renders itself, in this
  # language's own material. What it renders to is TEXT, because text is the only thing a model
  # reads.
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
  # Every word of it is the tenant's own, and that is the point: the view carries the operator's
  # authority, so nothing that arrived from outside the conversation may be spliced into it.
  # What memory and the knowledge base returned reaches the model as a tool result, in the
  # history, where a model reads it as information rather than as an instruction.
  #
  # Every state field is in scope by its own name, derived fields included, and so is what
  # surrounds the call: `resumed`, `call[:channel]`, `remembers?("médico habitual")`.
  class View
    # Where a class's view lives when nobody said: `views/<slug>.erb` beside the class's own file,
    # which is the convention this package has instead of a setting.
    def self.beside(file, slug) = File.join(File.dirname(file), "views", "#{slug}.erb")

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

    # Render the view against one reading of the state, and answer the text the model reads.
    def render(reading) = tidy(@erb.result(Context.new(reading).binding_for_the_template))

    # A template is written to be read by a person, so it is indented and spaced for one. What the
    # model reads is the same prose with the ragged edges taken off: no trailing spaces, never
    # more than one blank line in a row, nothing hanging off either end.
    def tidy(text)
      text.lines.map { |line| line.rstrip + "\n" }.join.gsub(/\n{3,}/, "\n\n").strip
    end

    # What a template is rendered in: the state by name, and the handful of helpers a prompt needs.
    #
    # Everything a template says that is not one of the helpers below is a question about the
    # state, so `stage`, `slots` and `resumed` read as the words they are — the same way an
    # instance variable reads in a Rails view, and refused the same way when nobody set it.
    class Context
      def initialize(reading)
        @reading = reading
      end

      # ERB needs somewhere to run. This is that place, and its scope is this object.
      def binding_for_the_template = binding

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
    end
  end
end
