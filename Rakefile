# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |task|
  task.libs = %w[lib test]
  task.test_files = FileList["test/**/*_test.rb"]
  task.warning = false
end

desc "The example's own ring-0 suite, run the way a customer runs theirs"
task :examples do
  ruby "-Ilib examples/clinica_norte/test/clinica-norte/clinica_test.rb"
end

# Ring 1 needs the one CLI and a key, so it is not part of `check`: the agents repository's nightly
# runs it. Without either it says what is missing and leaves.
desc "Ring 1: the example's goldens, through the one pinecall CLI and the gateway"
task :ring1 do
  checkout = File.expand_path("../agents/bin/pinecall.js", __dir__)
  cli = File.exist?(checkout) ? ["node", checkout] : (system("command -v pinecall >/dev/null") ? ["pinecall"] : nil)
  next puts("ring1: no pinecall CLI here — npm i -g pinecall, or check out ../agents") if cli.nil?
  next puts("ring1: no PINECALL_KEY — pinecall link in examples/clinica_norte") if ENV["PINECALL_KEY"].to_s.empty? && !File.exist?("examples/clinica_norte/.env")

  # The gem is this checkout's: the serve entry the CLI starts loads it from lib/.
  sh({ "RUBYLIB" => File.expand_path("lib", __dir__) }, *cli, "test", chdir: "examples/clinica_norte")
end

desc "Check the signatures against RBS"
task :rbs do
  sh "rbs -I sig validate"
end

desc "What CI runs: the tests, the example's own suite, then the signatures"
task check: %i[test examples rbs]

task default: :check
