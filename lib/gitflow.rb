require 'gitflow/natcmp'

Capistrano::Configuration.instance(true).load do |configuration|
    before "deploy:update_code", "gitflow:calculate_tag"
    namespace :gitflow do
        def last_tag_matching(pattern)
            matching_tags = `git tag -l '#{pattern}'`.split
            matching_tags.sort! do |a,b|
                String.natcmp(b,a,true)
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

        desc "Calculate the tag to deploy"
        task :calculate_tag do
            # make sure we have any other deployment tags that have been pushed by others so our auto-increment code doesn't create conflicting tags
            `git fetch`

            tagMethod = "tag_#{stage}"
            send tagMethod

            system 'git push'
            if $? != 0
                raise "git push failed"
            end

            system 'git push --tags'
            if $? != 0
                raise "git push --tags failed"
            end
        end

        desc "Show log between most recent staging tag (or given tag=XXX) and last production release."
        task :update_log do
            from_tag = nil
            to_tag = nil

            from_tag = if stage == :production
                         last_production_tag
                       elsif stage == :staging
                         last_staging_tag
                       else
                         raise "Unsupported stage #{stage}"
                       end

            # no idea how to properly test for an optional cap argument a la '-s tag=x'
            to_tag = configuration[:tag]
            if to_tag == nil
                puts "Calculating 'end' tag for :update_log for '#{stage}'"
                to_tag = if stage == :production
                           last_staging_tag
                         elsif stage == :staging
                           'head'
                         else
                           raise "Unsupported stage #{stage}"
                         end
            end

            log_subcommand = if ENV['git_log_command'] && ENV['git_log_command'].strip != ''
                               ENV['git_log_command']
                             else
                               'log'
                             end
            command = "git #{logSubcommand} #{fromTag}..#{toTag}"
            puts command
            system command
        end

        desc "Mark the current code as a staging/qa release"
        task :tag_staging do
            # find latest staging tag for today
            new_tag_date   = Date.today.to_s
            new_tag_serial = 1

            last_staging_tag = last_tag_matching("staging-#{new_tag_date}.*")
            if last_staging_tag
                # calculate largest serial and increment
                last_staging_tag =~ /staging-[0-9]{4}-[0-9]{2}-[0-9]{2}\.([0-9]*)/
                new_tag_serial = $1.to_i + 1
            end
            new_staging_tag = "staging-#{new_tag_date}.#{new_tag_serial}"

            current_sha = `git log --pretty=format:%H HEAD -1`
            last_staging_tag_sha = nil
            if last_staging_tag
                last_staging_tag_sha = `git log --pretty=format:%H #{last_staging_tag} -1`
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

        desc "Push the passed staging tag to production. Pass in tag to deploy with '-s tag=staging-YYYY-MM-DD.X'."
        task :tag_production do
            promote_to_production_tag = configuration[:tag]
            raise "Staging tag required; use '-s tag=staging-YYYY-MM-DD.X'" unless promote_to_production_tag
            raise "Staging tag required; use '-s tag=staging-YYYY-MM-DD.X'" unless promote_to_production_tag =~ /staging-.*/
            raise "Staging tag #{promote_to_production_tag} does not exist." unless last_tag_matching(promote_to_production_tag)
            
            promote_to_production_tag =~ /staging-([0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]*)/
            new_production_tag = "production-#{$1}"
            puts "promoting staging tag #{promote_to_production_tag} to production as '#{new_production_tag}'"
            system "git tag -a -m 'tagging current code for deployment to production' #{new_production_tag} #{promote_to_production_tag}"

            set :branch, new_production_tag
        end
    end
end
