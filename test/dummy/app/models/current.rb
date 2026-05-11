# Test stub. The engine's PayloadBuilder reads `::Current.user`,
# `::Current.workspace`, and `::Current.membership` to auto-attach
# context to every report. Real host apps define their own Current
# with whatever attributes they need; the engine just probes these
# three names.
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :workspace, :membership
end
