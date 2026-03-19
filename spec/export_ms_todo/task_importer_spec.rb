# frozen_string_literal: true

# spec/export_ms_todo/task_importer_spec.rb
require 'spec_helper'
require 'export_ms_todo/task_importer'
require 'export_ms_todo/graph_client'

RSpec.describe ExportMsTodo::TaskImporter do
  subject(:importer) { described_class.new(client, reporter: reporter) }

  let(:token) { 'Bearer test_token_123' }
  let(:client) { ExportMsTodo::GraphClient.new(token) }
  let(:reporter) { ExportMsTodo::NullReporter.new }

  let(:existing_lists_response) do
    double(body: {
      'value' => [
        { 'id' => 'existing-list-1', 'displayName' => 'Inbox' }
      ]
    }.to_json)
  end

  let(:create_list_response) do
    double(body: {
      'id' => 'new-list-1',
      'displayName' => 'My New List'
    }.to_json)
  end

  let(:create_task_response) do
    double(body: {
      'id' => 'task-1',
      'title' => 'Test task'
    }.to_json)
  end

  before do
    allow(client).to receive(:get)
      .with('/me/todo/lists?$top=100')
      .and_return(existing_lists_response)
  end

  describe '#import' do
    it 'raises ValidationError when task_lists is nil' do
      expect { importer.import(nil) }.to raise_error(ExportMsTodo::ValidationError)
    end

    it 'raises ValidationError when task_lists is empty' do
      expect { importer.import({}) }.to raise_error(ExportMsTodo::ValidationError)
    end

    context 'when creating tasks in an existing list' do
      let(:task_lists) do
        {
          'Inbox' => [
            { title: 'Test task', note: 'A note', due: '2026-03-20' }
          ]
        }
      end

      before do
        allow(client).to receive(:post)
          .with(%r{/me/todo/lists/existing-list-1/tasks}, body: anything)
          .and_return(create_task_response)
      end

      it 'reuses the existing list and creates the task' do
        created = importer.import(task_lists)
        expect(created).to eq(1)
        expect(client).not_to have_received(:post).with('/me/todo/lists', body: anything)
      end
    end

    context 'when creating tasks in a new list' do
      let(:task_lists) do
        {
          'My New List' => [
            { title: 'First task' },
            { title: 'Second task' }
          ]
        }
      end

      before do
        allow(client).to receive(:post)
          .with('/me/todo/lists', body: { displayName: 'My New List' })
          .and_return(create_list_response)

        allow(client).to receive(:post)
          .with(%r{/me/todo/lists/new-list-1/tasks}, body: anything)
          .and_return(create_task_response)
      end

      it 'creates the list and all tasks' do
        created = importer.import(task_lists)
        expect(created).to eq(2)
        expect(client).to have_received(:post).with('/me/todo/lists', body: { displayName: 'My New List' })
      end
    end

    context 'with due dates and notes' do
      let(:task_lists) do
        {
          'Inbox' => [
            { title: 'Task with due', due: '2026-04-01', note: 'Important' }
          ]
        }
      end

      before do
        allow(client).to receive(:post)
          .with(%r{/me/todo/lists/existing-list-1/tasks}, body: anything)
          .and_return(create_task_response)
      end

      it 'includes dueDateTime and body in the API call' do
        importer.import(task_lists)

        expect(client).to have_received(:post).with(
          "/me/todo/lists/existing-list-1/tasks",
          body: {
            title: 'Task with due',
            body: { content: 'Important', contentType: 'text' },
            dueDateTime: { dateTime: '2026-04-01T00:00:00', timeZone: 'Australia/Melbourne' }
          }
        )
      end
    end

    context 'with case-insensitive list matching' do
      let(:task_lists) do
        {
          'inbox' => [{ title: 'Test' }]
        }
      end

      before do
        allow(client).to receive(:post)
          .with(%r{/me/todo/lists/existing-list-1/tasks}, body: anything)
          .and_return(create_task_response)
      end

      it 'matches existing list names case-insensitively' do
        importer.import(task_lists)
        expect(client).not_to have_received(:post).with('/me/todo/lists', body: anything)
      end
    end
  end
end
