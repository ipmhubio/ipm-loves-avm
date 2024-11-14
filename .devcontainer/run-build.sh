#!/bin/bash

if [ "$#" -eq 1 ]; then
  fromCommit=$1
  pwsh -File "/workingfolder/src/scripts/build.ps1" -AvmRepositoryRootPath "/workingfolder/avm" -AvmPackageBuildRoot "/workingfolder/build" -FromCommit "$fromCommit"
else
  pwsh -File "/workingfolder/src/scripts/build.ps1" -AvmRepositoryRootPath "/workingfolder/avm" -AvmPackageBuildRoot "/workingfolder/build"
fi