# frozen_string_literal: true

require 'riemann'

require 'bundler/gem_tasks'

require 'github_changelog_generator/task'

GitHubChangelogGenerator::RakeTask.new :changelog do |config|
  config.user = 'riemann'
  config.project = 'riemann-ruby-client'
  config.exclude_labels = ['skip-changelog']
  config.future_release = "v#{Riemann::VERSION}"
  config.add_issues_wo_labels = false
end
