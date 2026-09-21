require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/generators/**/*_test.rb"]
end

desc "Generate a Rails app with the authentication and tenanting generators and run its tests"
task "test:integration" do
  Bundler.with_original_env { sh "bin/integration path" }
end

task default: :test
