# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |task|
  task.libs = %w[lib test]
  task.test_files = FileList["test/**/*_test.rb"]
  task.warning = false
end

desc "The example's own ring-0 suite, run the way a customer runs theirs"
task :examples do
  ruby "-Ilib examples/clinica_norte/test/clinica_test.rb"
end

desc "Check the signatures against RBS"
task :rbs do
  sh "rbs -I sig validate"
end

desc "What CI runs: the tests, the example's own suite, then the signatures"
task check: %i[test examples rbs]

task default: :check
