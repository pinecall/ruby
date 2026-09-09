# frozen_string_literal: true

module Pinecall
  # The prompt, cut where the cache is cut. Only `dynamic` may differ between two turns of a call.
  Regions = Data.define(:static, :history, :dynamic, :fills)

  # What the agent knows about this caller. The real one arrives with the memory card; a render
  # that nobody gave one to answers no to everything rather than guessing.
  class Remembered
    def initialize(facts = [])
      @facts = facts
    end

    # Whether the agent remembers something about this caller matching these words.
    def has?(text) = @facts.any? { |fact| fact.to_s.include?(text.to_s) }

    def to_a = @facts.dup
  end

  # The three regions a prompt is made of, in the one order they are ever sent.
  #
  # Nothing may reorder them: the cut between static and dynamic is where the provider's cache is
  # cut, and a static prefix that moves is a prefix nobody is paying less for.
  module Prompt
    # The macro a class declares its view with.
    module Declaring
      # The view this class renders its dynamic region with.
      #
      #     view                          # views/<slug>.erb beside this file — the convention
      #     view "views/reception.erb"    # somewhere else, relative to this file
      #     view template: <<~ERB         # small enough to live inside the class
      #
      # With nothing at all, the convention is looked up once and remembered, so an agent that
      # has a view beside it never says so and an agent that has none costs one `File.exist?`.
      def view(path = nil, template: nil)
        unless path.nil? && template.nil?
          @view = template ? View.inline(template, "#{name} (inline view)") : View.file(beside_this_file(path))
          return @view
        end
        return @view if defined?(@view)

        @view = view_of_this_class || (superclass.respond_to?(:view) ? superclass.view : nil)
      end

      # `views/<slug>.erb` beside the file the class was written in.
      def view_of_this_class
        here = source_file
        return nil if here.nil?

        path = View.beside(here, slug)
        File.exist?(path) ? View.file(path) : nil
      end

      # A path a class wrote is read from where that class lives, not from where a process ran.
      def beside_this_file(path)
        here = source_file
        return path if here.nil? || path.start_with?("/")

        File.expand_path(path, File.dirname(here))
      end

      def source_file
        found = name && Object.const_source_location(name)
        found&.first
      end
    end

    module_function

    # The whole prompt of this agent right now, region by region.
    def render(agent, resumed: false, memory: nil, line: nil)
      rendered = dynamic(agent, resumed:, memory:, line:)
      Regions.new(
        static: static(agent),
        history: history(agent),
        dynamic: rendered.text,
        fills: rendered.fills
      )
    end

    # The cached prefix: the class docstring, the knowledge marker, the framework's own words and
    # the tool docs. Nothing here may read the state — that is the whole point of the region.
    def static(agent)
      klass = agent.class
      words = Lang.words_for(klass)
      [
        agent.doc,
        klass.knowledge ? View.marker("knowledge", klass.knowledge.to_s) : nil,
        block("rules", words[:rules]),
        block("protocols", words[:protocols]),
        block("tools", tool_docs(agent))
      ].compact.reject { |part| part.strip.empty? }.join("\n\n")
    end

    # The runtime owns the turns, so the framework contributes only what it knows about them: the
    # summaries a `collapse` left where a stretch of the call used to be.
    def history(agent)
      agent.changes.select { |change| change.field == "@summary" }
           .map { |change| "#{View.marker("collapsed", JSON.generate({ seq: change.seq }))}\n#{change.next}" }
           .join("\n\n")
    end

    # The tail: the memory marker, the retrieval marker, and whatever the view says about now.
    def dynamic(agent, resumed: false, memory: nil, line: nil)
      view = agent.class.view
      return View::Rendered.new(text: "", fills: View::Fills.new) if view.nil?

      rendered = view.render(reading_for(agent, resumed:, memory:, line:))
      return rendered unless agent.class.memory && !rendered.text.include?("<!-- memory:")

      # A view that asks for memory itself decides where it goes; one that does not still gets it,
      # because a class configured with `memory` expects the caller to be remembered.
      opened = [View.marker("memory", "{}"), rendered.text].reject(&:empty?).join("\n\n")
      View::Rendered.new(text: opened, fills: rendered.fills)
    end

    # What a view is called with: the state and its derived fields, plus what surrounds the call.
    #
    # What the agent already knows about this caller reads as `remembered` and not as `memory`,
    # because in a template `memory` is the tag that writes the marker. One word, one meaning.
    def reading_for(agent, resumed: false, memory: nil, line: nil)
      Reading.new(agent.snapshot.merge(
                    remembered: memory || Remembered.new,
                    resumed:,
                    call: line || { channel: "web" }
                  ))
    end

    # The header a section of the printed page carries. One definition, so every page is ruled
    # the same way and `pinecall prompt` looks like `pinecall run --show-prompt`.
    def header_for(section) = "── #{section} ──"

    # The three regions as one page, each under its header, in order: what `pinecall prompt`
    # prints. The headers make it obvious at a glance which half of the prompt is cached.
    def show(agent, **context)
      regions = render(agent, **context)
      %i[static history dynamic]
        .map { |region| "#{header_for(region)}\n#{regions.public_send(region)}".rstrip }
        .join("\n\n")
    end

    # Every tool the class declares, visible right now or not: the model reads the docstring, and
    # the schema is what the wire carries.
    def tool_docs(agent)
      agent.tools.map { |spec| "- #{spec[:name]}: #{spec[:description]}" }.join("\n")
    end

    def block(name, body)
      body.to_s.empty? ? "" : "<#{name}>\n#{body}\n</#{name}>"
    end
  end
end
