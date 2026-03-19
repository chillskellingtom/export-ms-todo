# frozen_string_literal: true

# spec/export_ms_todo/importers/yaml_spec.rb
require 'spec_helper'
require 'export_ms_todo/importers/yaml'
require 'tmpdir'

RSpec.describe ExportMsTodo::Importers::Yaml do
  describe '#parse' do
    it 'raises ValidationError when file does not exist' do
      parser = described_class.new('/nonexistent/path.yml')
      expect { parser.parse }.to raise_error(ExportMsTodo::ValidationError, /File not found/)
    end

    it 'raises ValidationError when YAML has no lists key' do
      file = write_temp_yaml({ 'tasks' => [] })
      parser = described_class.new(file)
      expect { parser.parse }.to raise_error(ExportMsTodo::ValidationError, /expected 'lists' key/)
    end

    it 'raises ValidationError when lists are empty' do
      file = write_temp_yaml({ 'lists' => {} })
      parser = described_class.new(file)
      expect { parser.parse }.to raise_error(ExportMsTodo::ValidationError, /No lists defined/)
    end

    it 'raises ValidationError when a list has no tasks' do
      file = write_temp_yaml({ 'lists' => { 'Empty List' => [] } })
      parser = described_class.new(file)
      expect { parser.parse }.to raise_error(ExportMsTodo::ValidationError, /has no tasks/)
    end

    it 'raises ValidationError when a task is missing a title' do
      file = write_temp_yaml({ 'lists' => { 'My List' => [{ 'note' => 'no title' }] } })
      parser = described_class.new(file)
      expect { parser.parse }.to raise_error(ExportMsTodo::ValidationError, /missing a title/)
    end

    it 'raises ValidationError for invalid due date format' do
      file = write_temp_yaml({
                               'lists' => {
                                 'My List' => [{ 'title' => 'Task', 'due' => '20/03/2026' }]
                               }
                             })
      parser = described_class.new(file)
      expect { parser.parse }.to raise_error(ExportMsTodo::ValidationError, /invalid due date/)
    end

    it 'parses a valid YAML file' do
      file = write_temp_yaml({
                               'lists' => {
                                 'Work' => [
                                   { 'title' => 'Task one', 'note' => 'A note', 'due' => '2026-03-20' },
                                   { 'title' => 'Task two' }
                                 ],
                                 'Personal' => [
                                   { 'title' => 'Task three' }
                                 ]
                               }
                             })
      parser = described_class.new(file)
      result = parser.parse

      expect(result.keys).to contain_exactly(:Work, :Personal)
      expect(result[:Work].size).to eq(2)
      expect(result[:Work].first[:title]).to eq('Task one')
      expect(result[:Work].first[:due]).to eq('2026-03-20')
      expect(result[:Personal].size).to eq(1)
    end
  end

  private

  def write_temp_yaml(data)
    file = File.join(Dir.tmpdir, "test_import_#{rand(10_000)}.yml")
    File.write(file, YAML.dump(data))
    file
  end
end
