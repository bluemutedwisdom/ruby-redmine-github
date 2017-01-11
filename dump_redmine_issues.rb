#!/usr/bin/env ruby

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'optparse'
require 'yaml'
require 'redmine/general'
require 'redmine/project'
require 'github/issue'

Dir.chdir(File.dirname(__FILE__))

config = YAML.parse(File.read('settings.yml')).to_ruby
identifier = nil
use_cache = true

logger = Logger.new(STDERR)

OptionParser.new do |opts|
  opts.banner = 'Usage: dump_redmine_issues.rb [options]'

  opts.on('-h', '--help', 'Print help') do
    puts opts
    exit(1)
  end

  opts.on('-R name', '--redmine-project=name', 'Identifier of the Redmine project') do |n|
    identifier = n
  end

  opts.on('--[no-]cache', 'Ignore cached JSON files') do |v|
    use_cache = v
  end
end.parse!(ARGV)

Redmine.configure do |c|
  raise Exception, 'Redmine not configured in settings.yaml' unless config['redmine']
  config['redmine'].each do |k, v|
    c.public_send("#{k}=", v)
  end
end

raise Exception, 'Redmine project identifier not specified' unless identifier
project = Redmine::Project.find_by_identifier(identifier)

dump = "#{Dir.pwd}/dump"
Dir.mkdir(dump) unless Dir.exists?(dump)
dump = "#{dump}/#{identifier}"
Dir.mkdir(dump) unless Dir.exists?(dump)
Dir.mkdir("#{dump}/issue") unless Dir.exists?("#{dump}/issue")

#
# Get all RedMine issues
#
dump_file = "#{dump}/issues.json"

if use_cache && File.exists?(dump_file)
  logger.info('Getting issues from cache...')

  issues = YAML.parse(File.read(dump_file))
  issues = issues.to_ruby if issues.respond_to?(:to_ruby)
else
  logger.info('Indexing issues from Redmine...')
  issues = project.issues(
    project_id: project.id,
    status_id:  '*'
  ).map do |i| # map only core data
    {
      id: i.id,
      project: i.project.name,
      tracker: i.tracker.name,
      status: i.status.name,
      subject: i.subject
    }
  end

  GitHub::Utils.dump_to_file(dump_file, JSON.pretty_generate(issues))
end

logger.info("Found #{issues.length} issues, pulling them all")

issues.each do |i|
  id = i['id']
  dump_file = "#{dump}/issue/#{id}"
  json_file = "#{dump_file}.json"

  issue = nil
  if use_cache && File.exists?(json_file)
    logger.info("Loading issue \##{id} from cache")
    issue = Github::Issue.from_json(json_file)
  end

  unless issue
    logger.info("Loading issue \##{id} from Redmine")
    issue = Github::Issue.from_redmine(id)
    issue.dump_json(json_file)
  end

  issue.dump("#{dump_file}.md")
end