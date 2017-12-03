require "dotenv/substitutions/variable"
require "dotenv/substitutions/command" if RUBY_VERSION > "1.8.7"

module Dotenv
  class FormatError < SyntaxError; end

  # This class enables parsing of a string for key value pairs to be returned
  # and stored in the Environment. It allows for variable substitutions and
  # exporting of variables.
  class Parser
    @substitutions =
      [Dotenv::Substitutions::Variable, Dotenv::Substitutions::Command]

    LINE = /
      \A
      \s*
      (?:export\s+)?    # optional export
      ([\w\.]+)         # key
      (?:\s*=\s*|:\s+?) # separator
      (                 # optional value begin
        '(?:\'|[^'])*'  #   single quoted value
        |               #   or
        "(?:\"|[^"])*"  #   double quoted value
        |               #   or
        [^#\n]+         #   unquoted value
      )?                # value end
      \s*
      (?:\#.*)?         # optional comment
      \z
    /x

    class << self
      attr_reader :substitutions

      def call(string)
        new.call(string)
      end
    end

    def initialize
      @hash = {}
    end

    def call(string)
      string.split(/[\n\r]+/).each do |line|
        parse_line(line)
      end
      @hash
    end

    private

    def parse_line(line)
      if (match = line.match(LINE))
        key, value = match.captures
        @hash[key] = parse_value(value || "", @hash)
      elsif line.split.first == "export"
        if variable_not_set?(line, @hash)
          raise FormatError, "Line #{line.inspect} has an unset variable"
        end
      elsif line !~ /\A\s*(?:#.*)?\z/ # not comment or blank line
        raise FormatError, "Line #{line.inspect} doesn't match format"
      end
    end

    def parse_value(value, env)
      # Remove surrounding quotes
      expand_interpolations(
        expand_newlines_when_quoted(
          value.strip.sub(/\A(['"])(.*)\1\z/, '\2'),
          Regexp.last_match(1)),
        Regexp.last_match(1),
        env)
    end

    def expand_newlines_when_quoted(value, last_match)
      if last_match == '"'
        unescape_characters(expand_newlines(value))
      else
        value
      end
    end

    def expand_interpolations(initial_value, last_match, env)
      if last_match != "'"
        self.class.substitutions.inject(initial_value) do |value, proc|
          proc.call(value, env)
        end
      else
        initial_value
      end
    end

    def unescape_characters(value)
      value.gsub(/\\([^$])/, '\1')
    end

    def expand_newlines(value)
      value.gsub('\n', "\n").gsub('\r', "\r")
    end

    def variable_not_set?(line, env)
      !line.split[1..-1].all? { |var| env.member?(var) }
    end
  end
end
