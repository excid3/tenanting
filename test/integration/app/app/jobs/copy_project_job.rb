class CopyProjectJob < ApplicationJob
  def perform(project)
    Project.create!(name: "#{project.name} (copy)")
  end
end
