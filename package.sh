#!/usr/bin/env bash
 
# Builds a lambda package from a single Python 3 module with pip dependencies.
# A modified version of a script posted at: https://operatingops.com/2019/09/23/lambda-building-python-3-packages/
 
# https://stackoverflow.com/a/246128
SCRIPT_DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
OUTPUT_DIRECTORY=".package"
OUTPUT_FILE="smartsheet-webhook.zip"

pushd $SCRIPT_DIRECTORY > /dev/null
 
rm -rf $OUTPUT_DIRECTORY $OUTPUT_FILE
mkdir $OUTPUT_DIRECTORY
 
python -m pip install --target $OUTPUT_DIRECTORY --requirement requirements.txt
 
pushd $OUTPUT_DIRECTORY > /dev/null
zip --recurse-paths ${SCRIPT_DIRECTORY}/$OUTPUT_FILE .
popd > /dev/null
 
zip --grow $OUTPUT_FILE *.py
 
popd > /dev/null