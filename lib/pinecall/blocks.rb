# frozen_string_literal: true

module Pinecall
  # One named block of the prompt: which region it lives in, and its text right now.
  Block = Data.define(:name, :region, :text)

  # The whole prompt of one render: every block in send order, the history between the two
  # regions, and the render props the markers left behind.
  Blocks = Data.define(:blocks, :history, :fills) do
    # The text of one block, by name.
    def [](name) = blocks.find { |block| block.name == name.to_s }&.text

    # The blocks before the history: what the provider caches.
    def static = blocks.select { |block| block.region == "static" }

    # The blocks after the history: replaced every turn.
    def dynamic = blocks.select { |block| block.region == "dynamic" }

    # The static blocks as the model reads them, one text: joined, empty ones skipped.
    def instructions = static.map(&:text).reject(&:empty?).join("\n\n")
  end

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

  # The prompt as named blocks in two regions, in the one order they are ever sent.
  #
  # Static blocks go before the history and are what the provider caches; dynamic blocks go
  # after it and are replaced every turn. Nothing may reorder them: the cut between the two is
  # where the cache is cut, and a static block that reads the state is a block nobody is paying
  # less for. The framework's own four — `identity`, `knowledge`, `tools` and `view` — are the
  # layout when a class declares none; a class adds blocks of its own with `prompt`.
  module Prompt
    # The blocks every agent has, in send order: the layout of a class that adds none of its own.
    FRAMEWORK = [
      { name: "identity", region: "static" }.freeze,
      { name: "knowledge", region: "static" }.freeze,
      { name: "tools", region: "static" }.freeze,
      { name: "view", region: "dynamic" }.freeze
    ].freeze

    # The macros a class declares its prompt with: the view, and the blocks of its own.
    module Declaring
      # The view this class renders its `view` block with.
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

      # The blocks of this class's own, by region. Each one is `views/<slug>/<name>.erb` beside
      # this file, read here, so a block with no template is refused at load.
      #
      #     prompt static: %i[faq], dynamic: %i[availability]
      #
      # A static block is rendered once per call and cached, so it may not read the state; a
      # dynamic block is rendered on every change, after the history and before the view. The
      # line reads `slug`, so a class that names its own slug does so above this line.
      def prompt(static: [], dynamic: [])
        { "static" => static, "dynamic" => dynamic }.each do |region, names|
          names.each { |called| declare_block(called.to_s, region) }
        end
        layout
      end

      # Every block of this class in the order it is sent: the framework's static three, this
      # class's static blocks, its dynamic ones, and the view last. What `agent.configure` carries.
      def layout
        framework_static, view = FRAMEWORK.partition { |spec| spec[:region] == "static" }
        own = declared_blocks.map { |called, block| { name: called, region: block[:region] } }
        static, dynamic = own.partition { |spec| spec[:region] == "static" }
        framework_static + static + dynamic + view
      end

      # The template of one declared block, by name.
      def block_view(called) = declared_blocks.fetch(called)[:view]

      # The blocks this class declared, its parent's included, in declaration order.
      def declared_blocks
        @declared_blocks ||= superclass.respond_to?(:declared_blocks) ? superclass.declared_blocks.dup : {}
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

      private

      # One block, checked the way the gateway would check it and refused here instead: a name
      # the wire would not take, one of the framework's own, one declared twice, one with no file.
      def declare_block(called, region)
        spec = Protocol::Validate.call!("PromptBlockSpec", { name: called, region: }, where: "prompt #{called}")
        taken = FRAMEWORK.map { |spec| spec[:name] }
        if taken.include?(called)
          raise DeclarationRefused, "#{called} is one of the framework's own blocks " \
                                    "(#{taken.join(", ")}); call yours something else"
        end
        if declared_blocks.key?(called)
          raise DeclarationRefused, "#{name || "this agent"} declares the block #{called} twice"
        end

        declared_blocks[called] = { region: spec[:region], view: template_of_block(called) }
      rescue Protocol::ProtocolError => e
        raise DeclarationRefused, e.message
      end

      def template_of_block(called)
        here = source_file
        if here.nil?
          raise DeclarationRefused, "a block is a file beside the class, and #{called} has no class file to be beside"
        end

        path = View.beside(here, slug, block: called)
        raise DeclarationRefused, "#{called} has no template: write #{path}" unless File.exist?(path)

        View.file(path)
      end
    end

    module_function

    # The whole prompt of this agent right now, block by block, in send order.
    def render(agent, resumed: false, memory: nil, line: nil)
      fills = View::Fills.new
      reading = reading_for(agent, resumed:, memory:, line:)
      blocks = agent.class.layout.map do |spec|
        Block.new(name: spec[:name], region: spec[:region],
                  text: text_of(agent, spec[:name], spec[:region], reading, fills))
      end
      Blocks.new(blocks:, history: history(agent), fills:)
    end

    # The class docstring and the framework's own words: who the agent is, in every call.
    def identity(agent)
      words = Lang.words_for(agent.class)
      [agent.doc, tagged("rules", words[:rules]), tagged("protocols", words[:protocols])]
        .compact.reject { |part| part.strip.empty? }.join("\n\n")
    end

    # The marker the gateway opens the knowledge file into, or nothing.
    def knowledge(agent)
      file = agent.class.knowledge
      file ? View.marker("knowledge", file.to_s) : ""
    end

    # Every tool the class declares, visible right now or not: the model reads the docstring, and
    # the schema is what the wire carries.
    def tools(agent)
      docs = agent.tools.map { |spec| "- #{spec[:name]}: #{spec[:description]}" }.join("\n")
      tagged("tools", docs)
    end

    # The runtime owns the turns, so the framework contributes only what it knows about them: the
    # summaries a `collapse` left where a stretch of the call used to be.
    def history(agent)
      agent.changes.select { |change| change.field == "@summary" }
           .map { |change| "#{View.marker("collapsed", JSON.generate({ seq: change.seq }))}\n#{change.next}" }
           .join("\n\n")
    end

    # The view: the memory marker and whatever the template says about now.
    def view(agent, reading, fills)
      view = agent.class.view
      return "" if view.nil?

      text = view.render(reading, fills:, remembers: remembers(agent)).text
      return text unless agent.class.memory && !text.include?("<!-- memory:")

      # A view that asks for memory itself decides where it goes; one that does not still gets it,
      # because a class configured with `memory` expects the caller to be remembered.
      [View.marker("memory", "{}"), text].reject(&:empty?).join("\n\n")
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
    def header_for(section, region = nil) = "── #{[section, region && "(#{region})"].compact.join(" ")} ──"

    # The prompt as one page, a section per block under its header, the history between the two
    # regions: what `pinecall prompt` prints. The headers say at a glance what is cached.
    def show(agent, **context)
      rendered = render(agent, **context)
      sections = rendered.static.map { |block| [header_for(block.name, block.region), block.text] }
      sections << [header_for("history"), rendered.history]
      sections += rendered.dynamic.map { |block| [header_for(block.name, block.region), block.text] }
      sections.map { |header, text| "#{header}\n#{text}".rstrip }.join("\n\n")
    end

    # The text of one block: the framework's four by what they are, the class's own by its
    # template — against the state when dynamic, against a reading that refuses when static.
    def text_of(agent, called, region, reading, fills)
      case called
      when "identity" then identity(agent)
      when "knowledge" then knowledge(agent)
      when "tools" then tools(agent)
      when "view" then view(agent, reading, fills)
      else
        template = agent.class.block_view(called)
        read = region == "static" ? StaticReading.new(File.basename(template.path)) : reading
        template.render(read, fills:, remembers: remembers(agent)).text
      end
    end

    # The words a class said it remembers about a caller: the only categories a template may ask
    # the memory for by name, and none at all for a class that said nothing about it.
    def remembers(agent) = agent.class.memory&.dig(:remember) || []

    def tagged(name, body)
      body.to_s.empty? ? "" : "<#{name}>\n#{body}\n</#{name}>"
    end
  end
end
