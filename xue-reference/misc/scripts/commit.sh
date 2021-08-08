#!/usr/bin/env bash

set -e

PREVIOUS_DIR=$(pwd)
SCRIPT_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../.."

cd $PROJECT_ROOT

# update CODELINE.svg
LINE_OF_CODE=$(tokei $(find . -iname '*.nim') -o json | jq '.Nim.code')

if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' -E "s/LINES OF CODE: [0-9]+/LINES OF CODE: $LINE_OF_CODE/g" misc/badges/codeline.svg
    sed -i '' -E "s/textLength=\"250\">[0-9]+<\/text>/textLength=\"250\">$LINE_OF_CODE<\/text>/g" misc/badges/codeline.svg
else
    sed "s/LINES OF CODE: [[:digit:]]\+/LINES OF CODE: $LINE_OF_CODE/g" "misc/badges/codeline.svg"
    sed "s/textLength=\"210\">[[:digit:]]\+<\/text>/textLength=\"210\">$LINE_OF_CODE<\/text>/g" "misc/badges/codeline.svg"
fi

# commit as usual
git add .
git commit -S -m "$1"

# return to previous dir
cd "$PREVIOUS_DIR"
