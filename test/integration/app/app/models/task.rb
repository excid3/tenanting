class Task < ApplicationRecord
  belongs_to :project
  belongs_to :tag, optional: true
  has_many :comments, dependent: :destroy

  scoped_to_account through: :project
end
