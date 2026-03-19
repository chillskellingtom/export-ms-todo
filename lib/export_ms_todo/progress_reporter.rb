# frozen_string_literal: true

# lib/export_ms_todo/progress_reporter.rb
module ExportMsTodo
  # Tracks and reports progress during export operations
  class ProgressReporter
    attr_reader :total_tasks_in_ms, :exported_count, :completed_skipped, :failed_count

    def initialize(output:, verbose: false)
      @verbose = verbose
      @output = output # Thor instance for colored output

      # Metrics
      @total_tasks_in_ms = 0
      @exported_count = 0
      @completed_skipped = 0
      @failed_count = 0

      # Import metrics
      @imported_count = 0
      @import_total = 0
      @import_list_count = 0
      @mode = :export

      # Timing
      @start_time = nil

      # Per-list tracking for breakdown
      @list_stats = {} # { list_name => { exported:, completed:, failed: } }
      @current_list = nil
      @current_task_in_list = 0
      @total_tasks_in_current_list = 0
    end

    def start_export
      @start_time = Time.now
    end

    def finish_export
      # No-op, timing is calculated in print_summary
    end

    def start_fetching(list_count)
      @output.say 'Fetching tasks...', :green if list_count.positive?
    end

    def fetching_list(name, current, total)
      @current_list = name
      @current_task_in_list = 0
      @list_stats[name] ||= { exported: 0, completed: 0, failed: 0 }

      if @verbose
        @output.say "  → #{name} (#{current}/#{total})"
      else
        # Store for summary display later
        @list_stats[name][:position] = "#{current}/#{total}"
      end
    end

    def fetched_task(task, list_name)
      @current_task_in_list += 1
      @total_tasks_in_ms += 1

      # Count as exported (will be adjusted if it's completed)
      @exported_count += 1

      # Ensure list stats are initialized
      @list_stats[list_name] ||= { exported: 0, completed: 0, failed: 0 }
      @list_stats[list_name][:exported] += 1

      return unless @verbose

      @output.say "    Task: '#{task.title}' (#{@current_task_in_list}/#{@total_tasks_in_current_list})"
    end

    def skipped_completed_task(task)
      # Adjust counts - this task was counted as exported but is actually skipped
      @exported_count -= 1
      @completed_skipped += 1

      list_name = task.list_name || @current_list
      if @list_stats[list_name]
        @list_stats[list_name][:exported] -= 1
        @list_stats[list_name][:completed] += 1
      end

      return unless @verbose

      @output.say "    Skipped (completed): '#{task.title}'", :yellow
    end

    def failed_task(task_id, error)
      @failed_count += 1

      @list_stats[@current_list][:failed] += 1 if @current_list && @list_stats[@current_list]

      return unless @verbose

      @output.say "    ✗ Failed: #{task_id}", :red
      @output.say "      Error: #{error.message}", :red
    end

    def print_summary
      return unless @start_time

      duration = format_duration(Time.now - @start_time)

      print_summary_header
      print_task_counts
      print_list_breakdown
      @output.say "\nDuration: #{duration}"
      print_failure_warning
    end

    def increment_total_tasks(count = 1)
      @total_tasks_in_ms += count
    end

    def increment_exported(count = 1)
      @exported_count += count
    end

    def increment_completed_skipped(count = 1)
      @completed_skipped += count
    end

    def increment_failed(count = 1)
      @failed_count += count
    end

    # ─── Import-specific methods ──────────────────────────────────────────

    def start_import(list_count, task_count)
      @mode = :import
      @start_time = Time.now
      @import_list_count = list_count
      @import_total = task_count
      @imported_count = 0
      @output.say "Importing #{task_count} tasks across #{list_count} lists...", :green
    end

    def importing_list(name, current, total)
      @current_list = name
      @list_stats[name] ||= { imported: 0, failed: 0 }
      @output.say "  → #{name} (#{current}/#{total})" if @verbose
    end

    def imported_task(title, list_name)
      @imported_count += 1
      @list_stats[list_name] ||= { imported: 0, failed: 0 }
      @list_stats[list_name][:imported] += 1
      @output.say "    + #{title}" if @verbose
    end

    def failed_import(title, list_name, error)
      @failed_count += 1
      @list_stats[list_name][:failed] += 1 if list_name && @list_stats[list_name]
      @output.say "    ✗ #{title}: #{error.message}", :red if @verbose
    end

    def print_import_summary
      return unless @start_time

      duration = format_duration(Time.now - @start_time)

      @output.say "\n#{'━' * 50}"
      @output.say 'Import Summary'
      @output.say "#{'━' * 50}\n"
      @output.say "Tasks imported:  #{@imported_count}", :green
      @output.say "Failed:          #{@failed_count}", :red if @failed_count.positive?

      if @list_stats.any?
        @output.say "\nBreakdown by list:"
        @list_stats.each do |list_name, stats|
          count = stats[:imported] || 0
          line = "  #{list_name}: #{count} imported"
          line += ", #{stats[:failed]} failed" if stats[:failed]&.positive?
          @output.say line
        end
      end

      @output.say "\nDuration: #{duration}"
      print_failure_warning
    end

    private

    def print_summary_header
      @output.say "\n#{'━' * 50}"
      @output.say 'Export Summary'
      @output.say "#{'━' * 50}\n"
    end

    def print_task_counts
      @output.say "Total tasks in MS Todo:     #{@total_tasks_in_ms}"
      @output.say "  ✓ Exported:               #{@exported_count}", :green
      @output.say "  ⊘ Completed (skipped):     #{@completed_skipped}", :yellow if @completed_skipped.positive?
      @output.say "  ✗ Failed:                   #{@failed_count}", :red if @failed_count.positive?
    end

    def print_list_breakdown
      return unless @list_stats.any?

      @output.say "\nBreakdown by list:"
      @list_stats.each do |list_name, stats|
        summary = format_list_summary(stats)
        @output.say "  #{list_name}: #{summary}"
      end
    end

    def format_list_summary(stats)
      summary = "#{stats[:exported]} exported"
      summary += ", #{stats[:completed]} completed" if stats[:completed].positive?
      summary += ", #{stats[:failed]} failed" if stats[:failed].positive?
      summary
    end

    def print_failure_warning
      return unless @failed_count.positive?

      @output.say "\n⚠️  Note: #{@failed_count} tasks failed to export", :yellow
      @output.say 'Run with --verbose to see error details' unless @verbose
    end

    def format_duration(seconds)
      return "#{seconds.round}s" if seconds < 60

      minutes = (seconds / 60).floor
      remaining_seconds = (seconds % 60).round
      "#{minutes}m #{remaining_seconds}s"
    end
  end
end
