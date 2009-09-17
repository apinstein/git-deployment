Capistrano::Configuration.instance(true).load do
    before "deploy:update_code", "gitflow:calculate_tag"
    namespace :gitflow do
        desc "Calculate the tag to deploy"
        task :calculate_tag do
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

        desc "Mark the current code as a staging/qa release"
        task :tag_staging do
            # find latest staging tag for today
            newTagDate = Date.today.to_s 
            newTagSerial = 1

            todaysStagingTags = `git tag -l 'staging-#{newTagDate}.*'`
            todaysStagingTags = todaysStagingTags.split

            natcmpSrc = File.join(File.dirname(__FILE__), '/natcmp.rb')
            require natcmpSrc
            todaysStagingTags.sort! do |a,b|
                String.natcmp(b,a,true)
            end
            
            lastStagingTag = nil
            if todaysStagingTags.length > 0
                lastStagingTag = todaysStagingTags[0]

                # calculate largest serial and increment
                lastStagingTag =~ /staging-[0-9]{4}-[0-9]{2}-[0-9]{2}\.([0-9]*)/
                newTagSerial = $1.to_i + 1
            end
            newStagingTag = "staging-#{newTagDate}.#{newTagSerial}"

            shaOfCurrentCheckout = `git log --format=format:%H HEAD -1`
            shaOfLastStagingTag = nil
            if lastStagingTag
                shaOfLastStagingTag = `git log --format=format:%H #{lastStagingTag} -1`
            end

            if shaOfLastStagingTag == shaOfCurrentCheckout
                puts "Not re-tagging staging because the most recent tag (#{lastStagingTag}) already points to current head"
                newStagingTag = lastStagingTag
            else
                puts "Tagging current branch for deployment to staging as '#{newStagingTag}'"
                system "git tag -a #{newStagingTag}"
            end

            set :branch, newStagingTag
        end

        desc "Push the passed staging tag to production. Pass in tag to deploy with '-s tag=staging-YYYY-MM-DD.X'."
        task :tag_production do
            if !exists? :tag
                raise "staging tag required; use '-s tag=staging-YYYY-MM-DD.X'"
            end

            # get list of staging tags
            todaysStagingTags = `git tag -l 'staging-*' | sort -rn`
            todaysStagingTags = todaysStagingTags.split


            if !todaysStagingTags.include? tag
                raise "Staging Tag #{tag} does not exist."
            end
            
            tag =~ /staging-([0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]*)/
            newProductionTag = "production-#{$1}"
            puts "promoting staging tag #{tag} to production as '#{newProductionTag}'"
            system "git tag -a #{newProductionTag} #{tag}"

            set :branch, newProductionTag
        end
    end
end
