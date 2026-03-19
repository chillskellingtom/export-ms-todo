# frozen_string_literal: true

# lib/export_ms_todo.rb
require_relative 'export_ms_todo/version'
require_relative 'export_ms_todo/utils'
require_relative 'export_ms_todo/config'
require_relative 'export_ms_todo/task'
require_relative 'export_ms_todo/graph_client'
require_relative 'export_ms_todo/task_repository'
require_relative 'export_ms_todo/task_importer'
require_relative 'export_ms_todo/recurrence_mapper'

module ExportMsTodo
  class Error < StandardError; end
  class AuthenticationError < Error; end
  class RateLimitError < Error; end
  class ValidationError < Error; end
end
