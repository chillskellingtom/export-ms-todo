# frozen_string_literal: true

# lib/export_ms_todo/importers/yaml.rb
require 'yaml'

module ExportMsTodo
  module Importers
    # Parses a YAML task definition file into the structure expected by TaskImporter.
    #
    # Expected YAML format:
    #
    #   lists:
    #     "My List":
    #       - title: "Task title"
    #         note: "Optional note"
    #         due: "2026-03-20"
    #     "Another List":
    #       - title: "Another task"
    #
    class Yaml
      def initialize(path)
        @path = path
      end

      def parse
        raise ValidationError, "File not found: #{@path}" unless File.exist?(@path)

        data = YAML.load_file(@path, symbolize_names: true)
        raise ValidationError, "Invalid YAML: expected 'lists' key at top level" unless data.is_a?(Hash) && data[:lists]

        validate_and_normalise(data[:lists])
      end

      private

      def validate_and_normalise(lists)
        raise ValidationError, 'No lists defined in YAML file' if lists.nil? || lists.empty?

        lists.each do |list_name, tasks|
          raise ValidationError, "List '#{list_name}' has no tasks" if tasks.nil? || tasks.empty?

          tasks.each_with_index do |task, idx|
            unless task[:title] && !task[:title].strip.empty?
              raise ValidationError, "Task #{idx + 1} in '#{list_name}' is missing a title"
            end

            # Validate due date format if present
            if task[:due]
              unless task[:due].to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)
                raise ValidationError,
                      "Task '#{task[:title]}' in '#{list_name}' has invalid due date '#{task[:due]}' (expected YYYY-MM-DD)"
              end
            end
          end
        end

        lists
      end
    end
  end
end
