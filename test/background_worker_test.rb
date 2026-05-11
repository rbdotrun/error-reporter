require "test_helper"

class RbRunErrorReporter::Sdk::Ruby::BackgroundWorkerTest < ActiveSupport::TestCase
  Worker = RbRunErrorReporter::Sdk::Ruby::BackgroundWorker

  test "threads: 0 means synchronous (ImmediateExecutor)" do
    w = Worker.new(threads: 0)
    assert w.synchronous?
    executed = false
    assert w.submit { executed = true }
    assert executed, "submit must execute inline when synchronous"
  end

  test "submit catches exceptions inside the block — worker survives" do
    w = Worker.new(threads: 0)
    # Block raises; worker rescue swallows and returns true (accepted).
    assert_nothing_raised { w.submit { raise "boom" } }
    # And a follow-up submit still runs.
    ran = false
    w.submit { ran = true }
    assert ran
  end

  test "threads: > 0 is async — submit returns before the block runs" do
    w = Worker.new(threads: 2, max_queue: 2)
    refute w.synchronous?

    gate = Mutex.new
    cond = ConditionVariable.new
    started = false

    gate.synchronize { started = false }
    assert w.submit {
      gate.synchronize do
        started = true
        cond.signal
      end
    }

    gate.synchronize do
      cond.wait(gate, 2) until started
    end
    assert started, "background block should run on a worker thread within 2s"
    w.shutdown
  end

  test "shutdown waits for in-flight work" do
    w = Worker.new(threads: 1, shutdown_timeout: 2)
    flag = Concurrent::AtomicBoolean.new(false)
    w.submit { sleep 0.05; flag.make_true }
    w.shutdown
    assert flag.true?, "in-flight work should complete before shutdown returns"
  end
end
