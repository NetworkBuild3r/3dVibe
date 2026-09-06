require "test_helper"

class ScanBudgetTest < ActiveSupport::TestCase
  test "zero caps are unlimited" do
    budget = ScanBudget.unlimited
    10_000.times { budget.see_file! }
    10_000.times { budget.see_folder! }
    refute budget.exhausted?
    assert_nil budget.reason
  end

  test "file cap stops after the configured number of files" do
    budget = ScanBudget.new(max_seconds: 0, max_files: 2, max_folders: 0)
    refute budget.file_or_time_exceeded?
    budget.see_file!
    refute budget.file_exceeded?
    budget.see_file!
    assert budget.file_exceeded?
    assert_equal "files", budget.reason
  end

  test "folder cap is independent of files" do
    budget = ScanBudget.new(max_seconds: 0, max_files: 0, max_folders: 1)
    budget.see_folder!
    assert budget.folder_exceeded?
    assert_equal "folders", budget.reason
  end

  test "time cap uses a monotonic clock" do
    now = 0.0
    budget = ScanBudget.new(max_seconds: 2, max_files: 0, max_folders: 0, clock: -> { now })
    now = 1.5
    refute budget.time_exceeded?
    now = 2.0
    assert budget.time_exceeded?
    assert_equal "time", budget.reason
  end
end
