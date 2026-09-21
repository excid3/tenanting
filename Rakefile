require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/generators/**/*_test.rb"]
end

desc "Generate Rails apps with the authentication and tenanting generators and run their tests"
task "test:integration" do
  Bundler.with_original_env do
    %w[ path domain cookie ].each { |mode| sh "bin/integration #{mode}" }
  end
end

task default: :test
