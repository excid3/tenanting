class Project < ApplicationRecord
  scoped_to_account counter_cache: true

  has_many :tasks, dependent: :destroy
end
