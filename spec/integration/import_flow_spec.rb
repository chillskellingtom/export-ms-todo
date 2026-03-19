# frozen_string_literal: true

# spec/integration/import_flow_spec.rb
require 'spec_helper'
require 'export_ms_todo'
require 'export_ms_todo/graph_client'
require 'export_ms_todo/task_importer'
require 'export_ms_todo/importers/yaml'
require 'tmpdir'

RSpec.describe 'Full import flow', :integration do
  let(:token) { 'Bearer test_integration_token' }

  describe 'YAML import flow' do
    it 'parses YAML and creates lists and tasks via Graph API' do
      # Write a test YAML file
      yaml_content = <<~YAML
        lists:
          "Test List":
            - title: "First task"
              note: "With a note"
              due: "2026-04-01"
            - title: "Second task"
      YAML
      yaml_path = File.join(Dir.tmpdir, 'test_import_flow.yml')
      File.write(yaml_path, yaml_content)

      # Mock Graph API responses
      lists_response = double(body: { 'value' => [] }.to_json)

      create_list_response = double(body: {
        'id' => 'new-list-1',
        'displayName' => 'Test List'
      }.to_json)

      create_task_response = double(body: {
        'id' => 'new-task-1',
        'title' => 'First task'
      }.to_json)

      client = ExportMsTodo::GraphClient.new(token)
      allow(client).to receive(:get)
        .with('/me/todo/lists?$top=100')
        .and_return(lists_response)

      allow(client).to receive(:post)
        .with('/me/todo/lists', body: anything)
        .and_return(create_list_response)

      allow(client).to receive(:post)
        .with(%r{/me/todo/lists/new-list-1/tasks}, body: anything)
        .and_return(create_task_response)

      # Execute the full flow
      parser = ExportMsTodo::Importers::Yaml.new(yaml_path)
      task_lists = parser.parse

      importer = ExportMsTodo::TaskImporter.new(client)
      created = importer.import(task_lists)

      # Verify
      expect(created).to eq(2)
      expect(client).to have_received(:post).with('/me/todo/lists', body: { displayName: 'Test List' })
      expect(client).to have_received(:post).with(
        '/me/todo/lists/new-list-1/tasks',
        body: {
          title: 'First task',
          body: { content: 'With a note', contentType: 'text' },
          dueDateTime: { dateTime: '2026-04-01T00:00:00', timeZone: 'Australia/Melbourne' }
        }
      )
      expect(client).to have_received(:post).with(
        '/me/todo/lists/new-list-1/tasks',
        body: { title: 'Second task' }
      )
    ensure
      File.delete(yaml_path) if yaml_path && File.exist?(yaml_path)
    end
  end

  describe 'Error handling' do
    it 'handles authentication errors during import' do
      client = ExportMsTodo::GraphClient.new('invalid_token')
      allow(client).to receive(:get).and_raise(ExportMsTodo::AuthenticationError, 'Invalid token')

      importer = ExportMsTodo::TaskImporter.new(client)

      expect do
        importer.import({ 'Test' => [{ title: 'task' }] })
      end.to raise_error(ExportMsTodo::AuthenticationError, 'Invalid token')
    end
  end
end
