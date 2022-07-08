# shared scripts [![Build Status](https://github.com/elanthia-online/scripts/workflows/Build/badge.svg?branch=master)](https://github.com/elanthia-online/scripts/actions) [![Netlify Status](https://api.netlify.com/api/v1/badges/e54c4660-3793-40d5-964b-37cef0fb6a5e/deploy-status)](https://app.netlify.com/sites/goofy-einstein-b3362c/deploys)


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


