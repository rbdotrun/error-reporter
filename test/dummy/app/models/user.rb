# Minimal test stub. Real host apps define their own User; the engine
# only needs the constant + `.id` for PayloadBuilder's Current.user
# attachment to work.
class User < ApplicationRecord
end
