# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = true
end

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]

# Generate RBS files from rbs-inline annotations
desc "Generate RBS files with rbs-inline"
task :rbs do
  sh "bundle", "exec", "rbs-inline", "--output=sig", "lib"
end

# Run rbs-inline before building the gem
Rake::Task[:build].enhance([:rbs])
