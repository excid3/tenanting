class Comment < ApplicationRecord
  belongs_to :task

  scoped_to_account through: :task
end
