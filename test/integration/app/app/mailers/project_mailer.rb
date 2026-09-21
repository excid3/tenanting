class ProjectMailer < ApplicationMailer
  def created(project)
    @project = project
    mail to: "team@example.com", subject: "New project"
  end
end
