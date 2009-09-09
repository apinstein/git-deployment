Capistrano::Configuration.instance(true).load do
    before "deploy:update_code", "gitflow:calculate_tag"
    namespace :gitflow do
        desc "Calculate the tag to deploy"
        task :calculate_tag do
            tagMethod = "tag_#{stage}"
            send tagMethod

            # push tags and latest code
            `git push`
            `git push --tags`
        end

        desc "Mark the current code as a staging/qa release"
        task :tag_staging do
            # find latest staging tag for today
            newTagDate = Date.today.to_s 
            newTagSerial = 1

            stagingTags = `git tag -l 'staging-#{newTagDate}.*'`
            stagingTags = stagingTags.split

            natcmpSrc = File.join(File.dirname(__FILE__), '/natcmp.rb')
            require natcmpSrc
            stagingTags.sort! do |a,b|
                String.natcmp(b,a,true)
            end
            
            if stagingTags.length > 0
                # calculate largest serial and increment
                stagingTags[0] =~ /staging-[0-9]{4}-[0-9]{2}-[0-9]{2}\.([0-9]*)/
                newTagSerial = $1.to_i + 1
            end
            newStagingTag = "staging-#{newTagDate}.#{newTagSerial}"

            puts "Tagging current branch for deployment to staging as '#{newStagingTag}'"
            system "git tag #{newStagingTag}"

            set :branch, newStagingTag
        end

        desc "Push the passed staging tag to production. Pass in tag to deploy with '-s tag=staging-YYYY-MM-DD.X'."
        task :tag_production do
            if !exists? :tag
                raise "staging tag required; use '-s tag=staging-YYYY-MM-DD.X'"
            end

            # get list of staging tags
            stagingTags = `git tag -l 'staging-*' | sort -rn`
            stagingTags = stagingTags.split


            if !stagingTags.include? tag
                raise "Staging Tag #{tag} does not exist."
            end
            
            tag =~ /staging-([0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]*)/
            newProductionTag = "production-#{$1}"
            puts "promoting staging tag #{tag} to production as '#{newProductionTag}'"
            system "git tag #{newProductionTag} #{tag}"

            set :branch, newProductionTag
        end
    end
end
