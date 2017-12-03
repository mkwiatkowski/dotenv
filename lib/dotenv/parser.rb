require "dotenv/substitutions/variable"
require "dotenv/substitutions/command" if RUBY_VERSION > "1.8.7"

module Dotenv
  class FormatError < SyntaxError; end

  # This class enables parsing of a string for key value pairs to be returned
  # and stored in the Environment. It allows for variable substitutions and
  # exporting of variables.
  module Parser
    SUBSTITUTIONS =
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
      def call(string)
        string.split(/[\n\r]+/).inject({}) do |env, line|
          parse_line(line, env)
        end
      end

      private

      def parse_line(line, env)
        if (match = line.match(LINE))
          key, value = match.captures
          env.merge({key => parse_value(value || "", env)})
        elsif line.split.first == "export"
          if variable_not_set?(line, env)
            raise FormatError, "Line #{line.inspect} has an unset variable"
          else
            env
          end
        elsif line !~ /\A\s*(?:#.*)?\z/ # not comment or blank line
          raise FormatError, "Line #{line.inspect} doesn't match format"
        else
          env
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
          SUBSTITUTIONS.inject(initial_value) do |value, proc|
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
end
