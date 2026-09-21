class Tag < ApplicationRecord
  scoped_to_account optional: true
end
