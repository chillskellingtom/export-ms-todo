# frozen_string_literal: true

# lib/export_ms_todo/task_importer.rb
require 'json'
require_relative 'null_reporter'

module ExportMsTodo
  # Creates lists and tasks in Microsoft To Do via Graph API.
  # Mirrors TaskRepository (which reads); this class writes.
  class TaskImporter
    def initialize(client, reporter: nil)
      @client = client
      @reporter = reporter || NullReporter.new
    end

    # Import task lists from a parsed data structure.
    # Expected format: { "List Name" => [ { title:, note:, due: }, ... ], ... }
    def import(task_lists)
      raise ValidationError, 'No task lists provided' if task_lists.nil? || task_lists.empty?

      existing_lists = fetch_existing_lists
      total = task_lists.values.flatten.size
      @reporter.start_import(task_lists.size, total)

      created = 0
      task_lists.each_with_index do |(list_name, tasks), idx|
        @reporter.importing_list(list_name, idx + 1, task_lists.size)
        list_id = find_or_create_list(existing_lists, list_name)

        tasks.each do |task_def|
          create_task(list_id, task_def)
          created += 1
          @reporter.imported_task(task_def[:title] || task_def['title'], list_name)
        end
      end

      created
    end

    private

    def fetch_existing_lists
      response = @client.get('/me/todo/lists?$top=100')
      data = JSON.parse(response.body)
      data['value'] || []
    end

    def find_or_create_list(existing_lists, name)
      # Check for existing list (case-insensitive match)
      existing = existing_lists.find { |l| l['displayName'].downcase == name.downcase }
      return existing['id'] if existing

      # Create new list
      response = @client.post('/me/todo/lists', body: { displayName: name })
      data = JSON.parse(response.body)
      # Add to cache so subsequent lookups find it
      existing_lists << data
      data['id']
    end

    def create_task(list_id, task_def)
      title = task_def[:title] || task_def['title']
      note = task_def[:note] || task_def['note']
      due = task_def[:due] || task_def['due']

      body = { title: title }
      body[:body] = { content: note, contentType: 'text' } if note
      if due
        body[:dueDateTime] = {
          dateTime: "#{due}T00:00:00",
          timeZone: 'Australia/Melbourne'
        }
      end

      @client.post("/me/todo/lists/#{list_id}/tasks", body: body)
    end
  end
end
