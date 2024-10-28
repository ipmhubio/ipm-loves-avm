#!/bin/bash

# Prepare
pwsh -File "/workingfolder/src/scripts/prepare-tests.ps1" -AvmPackageBuildRoot "/workingfolder/build" -TestRootPath "/workingfolder/build-tests"

# Run Tests through Pester
pwsh -File "/workingfolder/src/scripts/run-tests.ps1" -TestRootPath "/workingfolder/build-tests"
