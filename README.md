# shared scripts [![Build Status](https://github.com/elanthia-online/scripts/workflows/Build/badge.svg?branch=master)](https://github.com/elanthia-online/scripts/actions)

This project is here to easily automate shared collaboration on scripts for Lich.

It will automatically publish changed scripts on merges to `master`

# collaboration

Successfully checking scripts into this repository requires three steps:

1. Make sure there are no naming conflicts and delete the script from ;repo
   so that it can be published from the shared environment using Travis-CI
2. Move the file into `scripts/`
3. Hard link the file back into your Lich script folder
   on Linux this works like `ln scripts/<script> <where you scripts are>`
4. Commit and open a PR against `master` from your fork as per usual

When you PR is merged it will trigger a build that publishes the newly collaborative script
under the author `elanthia-online` using the `util/repo` tool


