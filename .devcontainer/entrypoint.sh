#!/bin/bash

# Clone the AVM GitHub repo
if [ ! -d "/workingfolder/avm/.git" ]; then
  git clone https://github.com/Azure/bicep-registry-modules.git /workingfolder/avm
fi

exec "$@"