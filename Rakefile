require 'riemann'

require "bundler/gem_tasks"

require 'github_changelog_generator/task'

GitHubChangelogGenerator::RakeTask.new :changelog do |config|
  config.user = 'riemann'
  config.project = 'riemann-ruby-client'
  config.future_release = Riemann::VERSION
  config.add_issues_wo_labels = false
end
