# frozen_string_literal: true

require "digest"
require "json"
require "rake/testtask"

Rake::TestTask.new(:test) do |task|
  task.libs = %w[lib test]
  task.test_files = FileList["test/**/*_test.rb"]
  task.warning = false
end

desc "The example's own ring-0 suite, run the way a customer runs theirs"
task :examples do
  ruby "-Ilib -I../protocol/ruby/lib examples/clinica_norte/test/clinica_test.rb"
end

# The console is the one thing in this gem that is generated, and the only thing that needs Node.
# It is built in the repository next door and vendored here compiled; these two tasks are how it
# gets here and how a reader finds out that what is here is stale.
namespace :console do
  AGENTS = File.expand_path("../agents", __dir__)
  CONSOLE_SOURCE = "#{AGENTS}/src/cli/ui/console"
  BUILT = "console/BUILT.json"

  desc "Rebuild the console from ../agents and vendor it here"
  task :build do
    raise "there is no #{AGENTS} to build the console from" unless File.directory?(CONSOLE_SOURCE)

    sh "cd #{AGENTS} && pnpm exec vite build --config src/cli/ui/console/vite.config.ts"
    kept = File.read("console/README.md")
    rm_rf "console"
    cp_r "#{AGENTS}/dist/cli/ui/console", "console"
    File.write("console/README.md", kept)
    File.write(BUILT, JSON.pretty_generate({
                                             "source_sha256" => console_source_sha256,
                                             "built_at" => Time.now.utc.strftime("%Y-%m-%d"),
                                             "files" => Dir["console/**/*"].select { |one| File.file?(one) }.sort
                                           }))
    puts "console: vendored from #{AGENTS}"
  end

  desc "Say whether the vendored console is what its source would produce"
  task :check do
    unless File.directory?(CONSOLE_SOURCE)
      puts "console: ../agents is not checked out here, so nothing can be stale"
      next
    end
    said = File.exist?(BUILT) ? JSON.parse(File.read(BUILT))["source_sha256"] : nil
    now = console_source_sha256
    abort("console: the vendored bundle is stale — run `rake console:build`") unless said == now

    puts "console: current (#{now[0, 12]})"
  end

  # Every byte of the console's source, in one number. What was built is what this said at the
  # time; anything else means the bundle here is not what that source produces any more.
  def console_source_sha256
    files = Dir["#{CONSOLE_SOURCE}/**/*"].select { |one| File.file?(one) }.sort
    digest = Digest::SHA256.new
    files.each { |one| digest << one.delete_prefix(CONSOLE_SOURCE) << File.binread(one) }
    digest.hexdigest
  end
end

desc "Check the signatures against RBS"
task :rbs do
  sh "rbs -I sig validate"
end

desc "What CI runs: the console is what its source says, the tests, then the signatures"
task check: %i[console:check test examples rbs]

task default: :check
