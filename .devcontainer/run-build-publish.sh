#!/bin/bash

# Prepare Publish
pwsh -File "/workingfolder/src/scripts/prepare-publish.ps1" -AvmPackageBuildRoot "/workingfolder/build" -AvmPackagePublishRoot "/workingfolder/build-publish"
