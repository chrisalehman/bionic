#!/bin/bash
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/../lib/names.sh"

check "words are lower-cased and joined by one dash" "fix-the-stamp-reader" "$(slug_of 'Fix  the Stamp reader')"
check "punctuation at either end leaves no dash" "v2-notes" "$(slug_of '(v2: notes!)')"
check "text with no letter or digit has an empty slug" "" "$(slug_of '?! --')"
done_testing
