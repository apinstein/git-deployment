Capistrano::Configuration.instance(true).load do |configuration|
    before "deploy:update_code", "gitflow:calculate_tag"
    namespace :gitflow do
        def last_tag_matching(pattern)
            lastTag = nil

            allTagsMatching = `git tag -l '#{pattern}'`
            allTagsMatching = allTagsMatching.split
            natcmpSrc = File.join(File.dirname(__FILE__), '/natcmp.rb')
            require natcmpSrc
            allTagsMatching.sort! do |a,b|
                String.natcmp(b,a,true)
            end

            if allTagsMatching.length > 0
                lastTag = allTagsMatching[0]
            end
            return lastTag
        end

        def last_staging_tag()
            return last_tag_matching('staging-*')
        end

        def last_demo_tag()
            return last_tag_matching('demo-*')
        end

        def last_uat_tag()
            return last_tag_matching('uat-*')
        end        

        def last_production_tag()
            return last_tag_matching('production-*')
        end

        desc "Calculate the tag to deploy"
        task :calculate_tag do
            # make sure we have any other deployment tags that have been pushed by others so our auto-increment code doesn't create conflicting tags
            `git fetch`

            tagMethod = "tag_#{stage}"
            send tagMethod

            # push tags and latest code
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
            fromTag = nil
            toTag = nil

            # do different things based on stage
            if (stage == :production or stage = :production_vagrant)
                fromTag = last_tag_matching("#{stage}-*")
            elsif stage == :demo
                fromTag = last_demo_tag
            elsif stage == :uat
                fromTag = last_uat_tag                
            elsif (stage == :staging or stage = :staging_vagrant)
                fromTag = last_tag_matching("#{stage}-*")
            else
                raise "Unsupported stage #{stage}"
            end

            # no idea how to properly test for an optional cap argument a la '-s tag=x'
            toTag = configuration[:tag]
            if toTag == nil
                puts "Calculating 'end' tag for :update_log for '#{stage}'"
                # do different things based on stage
                if (stage == :production or stage = :production_vagrant)
                    toTag = last_staging_tag
                elsif stage == :demo
                    toTag = last_staging_tag
                elsif stage == :uat
                    toTag = last_staging_tag                    
                elsif (stage == :staging or stage = :staging_vagrant)
                    toTag = 'head'
                else
                    raise "Unsupported stage #{stage}"
                end
            end

            # run comp
            logSubcommand = 'log'
            if ENV['git_log_command'] && ENV['git_log_command'].strip != ''
                logSubcommand = ENV['git_log_command']
            end
            command = "git #{logSubcommand} #{fromTag}..#{toTag}"
            puts command
            system command
        end

        desc "Mark the current code as a staging/qa release"
        task :tag_staging do
            # find latest staging tag for today
            newTagDate = Date.today.to_s
            newTagSerial = 1

            lastStagingTag = last_tag_matching("staging-#{newTagDate}.*")
            if lastStagingTag
                # calculate largest serial and increment
                lastStagingTag =~ /staging-[0-9]{4}-[0-9]{2}-[0-9]{2}\.([0-9]*)/
                newTagSerial = $1.to_i + 1
            end
            newStagingTag = "staging-#{newTagDate}.#{newTagSerial}"

            shaOfCurrentCheckout = `git log --pretty=format:%H HEAD -1`
            shaOfLastStagingTag = nil
            if lastStagingTag
                shaOfLastStagingTag = `git log --pretty=format:%H #{lastStagingTag} -1`
            end

            if shaOfLastStagingTag == shaOfCurrentCheckout
                puts "Not re-tagging staging because the most recent tag (#{lastStagingTag}) already points to current head"
                newStagingTag = lastStagingTag
            else
                puts "Tagging current branch for deployment to staging as '#{newStagingTag}'"
                system "git tag -a -m 'tagging current code for deployment to staging' #{newStagingTag}"
            end

            set :branch, newStagingTag
        end

        desc "Push the passed staging tag to demo_vagrant. Pass in tag to deploy with '-s tag=staging-YYYY-MM-DD.X'."
        task :tag_demo_vagrant do
            promoteToDemoTag = configuration[:tag]
            raise "Staging tag required; use '-s tag=staging-YYYY-MM-DD.X'" unless promoteToDemoTag
            raise "Staging tag required; use '-s tag=staging-YYYY-MM-DD.X'" unless promoteToDemoTag =~ /staging-.*/
            raise "Staging Tag #{promoteToDemoTag} does not exist." unless last_tag_matching(promoteToDemoTag)
            
            promoteToDemoTag =~ /staging-([0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]*)/
            newDemoTag = "demo_vagrant-#{$1}"
            puts "promoting staging tag #{promoteToDemoTag} to demo_vagrant as '#{newDemoTag}'"
            system "git tag -a -m 'tagging current code for deployment to demo_vagrant' #{newDemoTag} #{promoteToDemoTag}"

            set :branch, newDemoTag
        end

        desc "Push the passed staging tag to demo. Pass in tag to deploy with '-s tag=staging-YYYY-MM-DD.X'."
        task :tag_demo do
            promoteToDemoTag = configuration[:tag]
            raise "Staging tag required; use '-s tag=staging-YYYY-MM-DD.X'" unless promoteToDemoTag
            raise "Staging tag required; use '-s tag=staging-YYYY-MM-DD.X'" unless promoteToDemoTag =~ /staging-.*/
            raise "Staging Tag #{promoteToDemoTag} does not exist." unless last_tag_matching(promoteToDemoTag)
            
            promoteToDemoTag =~ /staging-([0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]*)/
            newDemoTag = "demo-#{$1}"
            puts "promoting staging tag #{promoteToDemoTag} to demo as '#{newDemoTag}'"
            system "git tag -a -m 'tagging current code for deployment to demo' #{newDemoTag} #{promoteToDemoTag}"

            set :branch, newDemoTag
        end

        def generate_uat_tag()
            # find latest uat tag for today
            newTagDate = Date.today.to_s
            newTagSerial = 1

            lastUatTag = last_tag_matching("uat-#{newTagDate}.*")
            if lastUatTag
                # calculate largest serial and increment
                lastUatTag =~ /uat-[0-9]{4}-[0-9]{2}-[0-9]{2}\.([0-9]*)/
                newTagSerial = $1.to_i + 1
            end
            newUatTag = "uat-#{newTagDate}.#{newTagSerial}"

            shaOfCurrentCheckout = `git log --pretty=format:%H HEAD -1`
            shaOfLastUatTag = nil
            if lastUatTag
                shaOfLastUatTag = `git log --pretty=format:%H #{lastUatTag} -1`
            end

            if shaOfLastUatTag == shaOfCurrentCheckout
                puts "Not re-tagging uat because the most recent tag (#{lastUatTag}) already points to current head"
                newUatTag = lastUatTag
            else
                puts "Tagging current branch for deployment to uat as '#{newUatTag}'"
                system "git tag -a -m 'tagging current code for deployment to uat' #{newUatTag}"
            end
            return newUatTag
        end

        def staging_to_uat(promoteToUatTag)
            raise "Staging tag required; use '-s tag=staging-YYYY-MM-DD.X'" unless promoteToUatTag =~ /staging-.*/
            raise "Staging Tag #{promoteToUatTag} does not exist." unless last_tag_matching(promoteToUatTag)

            promoteToUatTag =~ /staging-([0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]*)/
            newUatTag = "uat-#{$1}"
            puts "promoting staging tag #{promoteToUatTag} to uat as '#{newUatTag}'"
            system "git tag -a -m 'tagging current code for deployment to uat' #{newUatTag} #{promoteToUatTag}"
            return newUatTag
        end

        desc "Mark the current code as a uat release"
        task :tag_uat do
            promoteToUatTag = configuration[:tag]
            #if the user inputs a -s tag=staging ...
            if promoteToUatTag
                newUatTag = staging_to_uat(promoteToUatTag)
            else
                newUatTag = generate_uat_tag
            end
            set :branch, newUatTag
        end  


        desc "Push the passed staging tag to production. Pass in tag to deploy with '-s tag=staging-YYYY-MM-DD.X'."
        task :tag_production do
            promoteToProductionTag = configuration[:tag]
            raise "Staging tag required; use '-s tag=staging-YYYY-MM-DD.X'" unless promoteToProductionTag
            raise "Staging tag required; use '-s tag=staging-YYYY-MM-DD.X'" unless promoteToProductionTag =~ /staging-.*/
            raise "Staging Tag #{promoteToProductionTag} does not exist." unless last_tag_matching(promoteToProductionTag)

            promoteToProductionTag =~ /staging-([0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]*)/
            newProductionTag = "production-#{$1}"
            puts "promoting staging tag #{promoteToProductionTag} to production as '#{newProductionTag}'"
            system "git tag -a -m 'tagging current code for deployment to production' #{newProductionTag} #{promoteToProductionTag}"

            set :branch, newProductionTag
        end

        desc "Mark the current code as a staging/qa release"
        task :tag_staging_vagrant do
            # find latest staging tag for today
            newTagDate = Date.today.to_s
            newTagSerial = 1

            lastStagingTag = last_tag_matching("staging_vagrant-#{newTagDate}.*")
            if lastStagingTag
                # calculate largest serial and increment
                lastStagingTag =~ /staging_vagrant-[0-9]{4}-[0-9]{2}-[0-9]{2}\.([0-9]*)/
                newTagSerial = $1.to_i + 1
            end
            newStagingTag = "staging_vagrant-#{newTagDate}.#{newTagSerial}"

            shaOfCurrentCheckout = `git log --pretty=format:%H HEAD -1`
            shaOfLastStagingTag = nil
            if lastStagingTag
                shaOfLastStagingTag = `git log --pretty=format:%H #{lastStagingTag} -1`
            end

            if shaOfLastStagingTag == shaOfCurrentCheckout
                puts "Not re-tagging staging_vagrant because the most recent tag (#{lastStagingTag}) already points to current head"
                newStagingTag = lastStagingTag
            else
                puts "Tagging current branch for deployment to staging_vagrant as '#{newStagingTag}'"
                system "git tag -a -m 'tagging current code for deployment to staging_vagrant' #{newStagingTag}"
            end

            set :branch, newStagingTag
        end

        desc "Push the passed staging tag to production_vagrant. Pass in tag to deploy with '-s tag=staging-YYYY-MM-DD.X'."
        task :tag_production_vagrant do
            promoteToProductionTag = configuration[:tag]
            raise "Staging tag required; use '-s tag=staging-YYYY-MM-DD.X'" unless promoteToProductionTag
            raise "Staging tag required; use '-s tag=staging-YYYY-MM-DD.X'" unless promoteToProductionTag =~ /staging-.*/
            raise "Staging Tag #{promoteToProductionTag} does not exist." unless last_tag_matching(promoteToProductionTag)

            promoteToProductionTag =~ /staging-([0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]*)/
            newProductionTag = "production_vagrant-#{$1}"
            puts "promoting staging tag #{promoteToProductionTag} to production_vagrant as '#{newProductionTag}'"
            system "git tag -a -m 'tagging current code for deployment to production_vagrant' #{newProductionTag} #{promoteToProductionTag}"

            set :branch, newProductionTag
        end
    end
end
