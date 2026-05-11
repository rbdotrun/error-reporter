require "test_helper"

class RbRunErrorReporter::Sdk::Ruby::DedupTest < ActiveSupport::TestCase
  Dedup = RbRunErrorReporter::Sdk::Ruby::Dedup

  setup { Dedup.reset! }

  test "window=0 disables dedup entirely" do
    exc = build_with_backtrace("dup")
    refute Dedup.duplicate?(exc, window: 0)
    refute Dedup.duplicate?(exc, window: 0)
  end

  test "second identical exception within window is reported as duplicate" do
    exc = build_with_backtrace("dup")
    refute Dedup.duplicate?(exc, window: 60)
    assert Dedup.duplicate?(exc, window: 60)
  end

  test "different exception class is not a duplicate" do
    a = build_with_backtrace("dup")
    b = ArgumentError.new("dup")
    b.set_backtrace(a.backtrace)

    refute Dedup.duplicate?(a, window: 60)
    refute Dedup.duplicate?(b, window: 60)
  end

  test "different message is not a duplicate" do
    a = build_with_backtrace("one")
    b = build_with_backtrace("two")

    refute Dedup.duplicate?(a, window: 60)
    refute Dedup.duplicate?(b, window: 60)
  end

  private

    def build_with_backtrace(msg)
      raise msg
    rescue RuntimeError => e
      e
    end
end
