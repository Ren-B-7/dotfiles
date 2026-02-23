#!/bin/bash
# Usage: ./missing.sh <should_have.list> <installed.list>
# Prints the programs from the first list that are missing from the second.

if [ $# -ne 2 ]; then
    echo "Usage: $0 <should_have.list> <installed.list>"
    exit 1
fi

should_have="$1"
installed="$2"

# Print missing programs
comm -23 <(sort "$should_have") <(sort "$installed")
