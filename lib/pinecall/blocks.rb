# frozen_string_literal: true

module Pinecall
  # One named block of the prompt: which region it lives in, and its text right now.
  Block = Data.define(:name, :region, :text)

  # The whole prompt of one render: every block in send order, and the history between the two
  # regions.
  Blocks = Data.define(:blocks, :history) do
    # The text of one block, by name.
    def [](name) = blocks.find { |block| block.name == name.to_s }&.text

    # The blocks before the history: what the provider caches.
    def static = blocks.select { |block| block.region == "static" }

    # The blocks after the history: replaced every turn.
    def dynamic = blocks.select { |block| block.region == "dynamic" }

    # The static blocks as the model reads them, one text: joined, empty ones skipped.
    def instructions = static.map(&:text).reject(&:empty?).join("\n\n")
  end

  # The prompt as named blocks in two regions, in the one order they are ever sent.
  #
  # Static blocks go before the history and are what the provider caches; the view goes after it
  # and is replaced every turn. Nothing may reorder them: the cut between the two is where the
  # cache is cut. Every one of them is the tenant's own words — the class docstring, the file it
  # knows by heart, its tools' comments, its view — and nothing else is ever put in them: what a
  # lookup returned reaches the model as a tool result, in the history.
  module Prompt
    # The blocks every agent has, in send order. There are four, the same four for everybody.
    FRAMEWORK = [
      { name: "identity", region: "static" }.freeze,
      { name: "knowledge", region: "static" }.freeze,
      { name: "tools", region: "static" }.freeze,
      { name: "view", region: "dynamic" }.freeze
    ].freeze

    # The macro a class declares its view with.
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

    # The whole prompt of this agent right now, block by block, in send order.
    def render(agent, resumed: false, remembered: [], line: nil)
      reading = reading_for(agent, resumed:, remembered:, line:)
      blocks = FRAMEWORK.map do |spec|
        Block.new(name: spec[:name], region: spec[:region], text: text_of(agent, spec[:name], reading))
      end
      Blocks.new(blocks:, history: history(agent))
    end

    # The class docstring and the framework's own words: who the agent is, in every call.
    def identity(agent)
      words = Lang.words_for(agent.class)
      [agent.doc, tagged("rules", words[:rules]), tagged("protocols", words[:protocols])]
        .compact.reject { |part| part.strip.empty? }.join("\n\n")
    end

    # The one file the agent knows by heart, whole. It is a file the tenant writes and ships with
    # the class, so it is the operator's own words and belongs with them, in the cached prefix.
    # The day it stops being written by hand it belongs in a knowledge base instead, which is
    # retrieved and reaches the model as a tool result.
    def knowledge(agent) = agent.class.knowledge_text.to_s.strip

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
           .map { |change| "#{collapsed(change.seq)}\n#{change.next}" }
           .join("\n\n")
    end

    # Where a stretch of the call used to be. The one line this package writes that is not prose.
    def collapsed(seq) = "<!-- collapsed: #{JSON.generate({ seq: })} -->"

    # The view: what the template says about now, and nothing else.
    def view(agent, reading)
      view = agent.class.view
      view.nil? ? "" : view.render(reading)
    end

    # What a view is called with: the state and its derived fields, what surrounds the call, and
    # what the agent already knows about this caller — which it may ask about, never print.
    def reading_for(agent, resumed: false, remembered: [], line: nil)
      Reading.new(agent.snapshot.merge(resumed:, call: line || { channel: "web" }), remembered)
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

    # The text of one block, by what that block is.
    def text_of(agent, called, reading)
      case called
      when "identity" then identity(agent)
      when "knowledge" then knowledge(agent)
      when "tools" then tools(agent)
      when "view" then view(agent, reading)
      end
    end

    def tagged(name, body)
      body.to_s.empty? ? "" : "<#{name}>\n#{body}\n</#{name}>"
    end
  end
end
