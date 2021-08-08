#!/usr/bin/env bash

set -e

PREVIOUS_DIR=$(pwd)
SCRIPT_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../.."

cd $PROJECT_ROOT

# update CODELINE.svg
LINE_OF_CODE=$(tokei $(find . -iname '*.nim') -o json | jq '.Nim.code')

sed -i "s/LINES OF CODE: [[:digit:]]\+/LINES OF CODE: $LINE_OF_CODE/g" misc/badges/CODELINE.svg
sed -i "s/textLength=\"210\">[[:digit:]]\+<\/text>/textLength=\"210\">$LINE_OF_CODE<\/text>/g" misc/badges/CODELINE.svg

# commit as usual
git add .
git commit -S -m "$1"

# return to previous dir
cd "$PREVIOUS_DIR"
