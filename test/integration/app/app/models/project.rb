class Project < ApplicationRecord
  scoped_to_account

  has_many :tasks, dependent: :destroy
end
