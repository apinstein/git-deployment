require 'capistrano'
require 'capistrano/gitflow/natcmp'
require 'stringex'

module Capistrano
  class Gitflow
    def self.load_into(capistrano_configuration)
      capistrano_configuration.load do
        before "deploy:update_code", "gitflow:calculate_tag"
        before "gitflow:calculate_tag", "gitflow:verify_up_to_date"

        namespace :gitflow do
          def last_tag_matching(pattern)
            matching_tags = `git tag -l '#{pattern}'`.split
            matching_tags.sort! do |a,b|
              String.natcmp(b, a, true)
            end

            last_tag = if matching_tags.length > 0
                         matching_tags[0]
                       else
                         nil
                       end
          end

          def last_staging_tag()
            last_tag_matching('staging-*')
          end

          def last_production_tag()
            last_tag_matching('production-*')
          end

          task :verify_up_to_date do
            set :local_branch, `git branch --no-color 2> /dev/null | sed -e '/^[^*]/d'`.gsub(/\* /, '').chomp
            set :local_sha, `git log --pretty=format:%H HEAD -1`.chomp
            set :origin_sha, `git log --pretty=format:%H origin/#{local_branch} -1`
            unless local_sha == origin_sha
              abort """
Your #{local_branch} branch is not up to date with origin/#{local_branch}.
Please make sure you have pulled and pushed all code before deploying:

    git pull origin #{local_branch}
    #run tests, etc
    git push origin #{local_branch}

    """
            end
          end



          desc "Calculate the tag to deploy"
          task :calculate_tag do
            # make sure we have any other deployment tags that have been pushed by others so our auto-increment code doesn't create conflicting tags
            `git fetch`

            send "tag_#{stage}"

            system "git push --tags origin #{local_branch}"
            if $? != 0
              abort "git push failed"
            end
          end

          desc "Show log between most recent staging tag (or given tag=XXX) and last production release."
          task :commit_log do
            from_tag = if stage == :production
                         last_production_tag
                       elsif stage == :staging
                         last_staging_tag
                       else
                         abort "Unsupported stage #{stage}"
                       end

            # no idea how to properly test for an optional cap argument a la '-s tag=x'
            to_tag = configuration[:tag]
            to_tag ||= begin 
                         puts "Calculating 'end' tag for :commit_log for '#{stage}'"
                         to_tag = if stage == :production
                                    last_staging_tag
                                  elsif stage == :staging
                                    'head'
                                  else
                                    abort "Unsupported stage #{stage}"
                                  end
                       end


            command = if `git config remote.origin.url` =~ /git@github.com:(.*)\/(.*).git/
                        "open https://github.com/#{$1}/#{$2}/compare/#{from_tag}...#{to_tag || 'master'}"
                      else
                        log_subcommand = if ENV['git_log_command'] && ENV['git_log_command'].strip != ''
                                           ENV['git_log_command']
                                         else
                                           'log'
                                         end
                        "git #{log_subcommand} #{fromTag}..#{toTag}"
                      end
            puts command
            system command
          end

          desc "Mark the current code as a staging/qa release"
          task :tag_staging do
            # find latest staging tag for today
            new_tag_date   = Date.today.to_s
            new_tag_serial = 1

            who = `whoami`.chomp.to_url
            what = Capistrano::CLI.ui.ask("What does this release introduce? (this will be normalized and used in the tag for this release) ").to_url

            last_staging_tag = last_tag_matching("staging-#{new_tag_date}.*")
            if last_staging_tag
              # calculate largest serial and increment
              last_staging_tag =~ /staging-[0-9]{4}-[0-9]{2}-[0-9]{2}\-([0-9]*)/
                new_tag_serial = $1.to_i + 1
            end

            new_staging_tag = "#{stage}-#{new_tag_date}-#{new_tag_serial}-#{who}-#{what}"

            current_sha = `git log --pretty=format:%H HEAD -1`
            last_staging_tag_sha = if last_staging_tag
                                     `git log --pretty=format:%H #{last_staging_tag} -1`
                                   end

            if last_staging_tag_sha == current_sha
              puts "Not re-tagging staging because the most recent tag (#{last_staging_tag}) already points to current head"
              new_staging_tag = last_staging_tag
            else
              puts "Tagging current branch for deployment to staging as '#{new_staging_tag}'"
              system "git tag -a -m 'tagging current code for deployment to staging' #{new_staging_tag}"
            end

            set :branch, new_staging_tag
          end

          desc "Push the approved tag to production. Pass in tag to deploy with '-s tag=staging-YYYY-MM-DD-X-feature'."
          task :tag_production do
            promote_to_production_tag = configuration[:tag]

            unless promote_to_production_tag && promote_to_production_tag =~ /staging-.*/
              abort "Staging tag required; use '-s tag=staging-YYYY-MM-DD.X'"
            end
            unless last_tag_matching(promote_to_production_tag)
              abort "Staging tag #{promote_to_production_tag} does not exist."
            end

            promote_to_production_tag =~ /^staging-(.*)$/
              new_production_tag = "production-#{$1}"
            puts "promoting staging tag #{promote_to_production_tag} to production as '#{new_production_tag}'"
            system "git tag -a -m 'tagging current code for deployment to production' #{new_production_tag} #{promote_to_production_tag}"

            set :branch, new_production_tag
          end
        end

        namespace :deploy do
          namespace :pending do
            task :compare do
              gitflow.commit_log
            end
          end
        end
      end

    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Gitflow.load_into(Capistrano::Configuration.instance)
end
