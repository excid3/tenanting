class Project < ApplicationRecord
  include AccountScoped
  has_many :tasks, dependent: :destroy
end
