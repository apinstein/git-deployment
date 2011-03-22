A Capistrano recipe for git deployment via tags in a multistage environment.
===

The best thing about this recipe is that there is almost nothing to learn -- your cap deploy process barely changes.
Gitflow simply adds some tagging/logging/workflow magic.

Examples
---

BEFORE

    cap deploy              # 'head' goes to staging
    cap production deploy   # 'head' goes to production

AFTER

    cap deploy                                                  # 'head' goes to staging; tag staging-YYYY-MM-DD.X created
    cap production deploy -s tag=staging-YYYY-MM-DD.X           # tag 'staging-YYYY-MM-DD.X' goes to production
                                                            # tag 'production-YYYY-MM-DD.X' created; points to staging tag

BONUS

    cap gitflow:update_log              # shows you a log of what will be pushed to staging that isn't already there
    cap production gitflow:update_log   # shows you a log of what will be pushed to production that isn't already there

INSTALLATION
====

require the gitflow file after your multistage require
  
    require 'capistrano/ext/multistage'
    require 'git-deployment/gitflow.rb'

<b>Expects stages "staging" and "production".</b>

DETAILS
---

After experimenting with several workflows for deployment in git, I've finally found one I really like.

* You can push to staging at any time; every staging push is automatically tagged with a unique tag.
* You can only push a staging tag to production. This helps to enforce QA of all pushes to production.

PUSH TO STAGING:
---

Whenever you want to push the currently checked-out code to staging, just do:

    cap staging deploy

gitflow will automatically:

* create a unique tag in the format of 'staging-YYYY-MM-DD.X'
* configure multistage to use that tag for the deploy
* push the code and tags to the remote "origin"
* and run the normal deploy task for the staging stage.

PUSH TO PRODUCTION:
---

Whenever you want to push code to production, you must specify the staging tag you wish to promote to production:

    cap production deploy -s tag=staging-2009-09-08.2

gitflow will automatically:

* alias the staging tag to a production tag like: production-2008-09-08.2
* configure multistage to use that tag for the deploy
* push the code and tags to the remote "origin"
* and run the normal deploy task for the production stage.

NOTES:
---

* you may need to wipe out the cached-copy on the remote server that cap uses when switching to this workflow; I have seen situations where the cached copy cannot cleanly checkout to the new branch/tag. it's safe to try without wiping it out first, it will fail gracefully.
* if your stages already have a "set :branch, 'my-staging-branch'" call in your configs, remove it. This workflow configures it automatically.
* it'd be cool to package this up as a gem to make installation easier; don't know how at the moment. just clone the code...
