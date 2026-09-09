# frozen_string_literal: true

module Pinecall
  class Agent
    # The comment above a class or a method, read back out of the source file: the prompt.
    #
    # A docstring is the one part of a declaration a model actually reads, so it must live where
    # the person writing the tool is already looking — right above it, in the comment they would
    # have written anyway. Ruby keeps `#` comments out of the object, but it does keep where every
    # method was defined, and the file is still on disk: `source_location` says the line, and the
    # comment block above it is the docstring. The TypeScript side parses its own source with oxc
    # to reach the same two lines; here it is `File.readlines` and a walk upward.
    #
    # The walk steps over the declaration macros between the comment and the `def`, so the natural
    # layout works and nobody has to remember an order:
    #
    #     # Busca al paciente por nombre y teléfono.
    #     tool stage: :identify, pii: %i[name phone]
    #     def find_patient(name:, phone:)
    #
    # A class built at runtime has no file to read. It says so with `doc "…"` instead, and every
    # message that needs a docstring names both doors.
    module Doc
      # Where the walk stops when it has found no comment: the end of whatever came before.
      ENDS_WHAT_CAME_BEFORE = /\A\s*(end\b|def\b|class\b|module\b)/
      COMMENT = /\A\s*#(?!\s*(frozen_string_literal|rubocop|:nodoc:))\s?(.*)\z/

      class << self
        # The comment above a class's own `class` line, or nil when there is nothing to read.
        def for_class(klass)
          declared = klass.instance_variable_get(:@pinecall_doc)
          return declared unless declared.nil?
          return nil if klass.name.nil?

          where = Object.const_source_location(klass.name)
          where.nil? ? nil : above(*where)
        end

        # The comment above one method of a class, or nil.
        def for_method(klass, name)
          where = klass.instance_method(name).source_location
          where.nil? ? nil : above(*where)
        end

        # The comment block that ends just above `line` of `file`, as one string, or nil.
        def above(file, line)
          lines = source(file)
          return nil if lines.empty?

          # Step over the declaration between the comment and the `def`, however many lines it
          # runs to. A blank line ends the walk, which is what makes "the comment sits directly
          # above" the rule rather than "somewhere above".
          at = line - 2
          at -= 1 while at >= 0 && !lines[at].match?(COMMENT) &&
                        !lines[at].strip.empty? && !lines[at].match?(ENDS_WHAT_CAME_BEFORE)
          block = []
          while at >= 0 && (said = lines[at].match(COMMENT))
            block.unshift(said[2].rstrip)
            at -= 1
          end
          text = block.join("\n").strip
          text.empty? ? nil : text
        end

        # A file is read once per process: a class declares its tools at load and never again,
        # and a running agent must not touch the disk between two turns of a call.
        def source(file)
          @source ||= {}
          @source[file] ||= File.exist?(file) ? File.readlines(file, chomp: true) : []
        end

        # Forget what was read. A test that rewrites a file and reloads it needs this; nothing else.
        def forget = @source = {}
      end
    end
  end
end
