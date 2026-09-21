class Task < ApplicationRecord
  belongs_to :project
  include AccountScoped
end
