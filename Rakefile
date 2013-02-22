#!/usr/bin/env rake
# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require File.expand_path('../config/application', __FILE__)

Tracksapp::Application.load_tasks

Rake::TestTask.new([:test, :lockdown]) do |t|
  t.test_files = FileList[
    'test/functional/lockdown_test.rb'
  ]
end

Rake::TestTask.new([:test, :stats]) do |t|
  t.test_files = FileList[
    'test/functional/stats_controller_test.rb'
  ]
end

desc "run stats features"
namespace :cucumber do
  task :stats do
    sh "bundle exec cucumber features/show_statistics.feature"
  end
end

desc "run stats tests and features"
task :wip do
  Rake::Task['test:stats'].invoke
  Rake::Task['cucumber:stats'].invoke
end