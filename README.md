# shared scripts [![Build Status](https://travis-ci.org/elanthia-online/scripts.svg?branch=master)](https://travis-ci.org/elanthia-online/scripts)

this project is here to easily automate shared collaboration on scripts for Lich.

it will automatically publish changed scripts on merges to `master`

# collaboration

successfully checking scripts into this repository requires three steps:

1. make sure there are no naming conflicts and delete the script from ;repo
   so that it can be published from the shared environment using Travis-CI
2. move the file into `scripts/`
3. hard link the file back into your Lich script folder
   on Linux this works like `ln scripts/<script> <where you scripts are>`
4. commit and open a PR against `master` from your fork as per usual

When you PR is merged it will trigger a build that publishes the newly collaborative script
under the author `elanthia-online` using the `util/repo` tool