#!/bin/bash
# lib/names.sh — the names trellis derives from text.

# slug_of <text> — <text> lower-cased, each run of characters other than a-z and 0-9 turned
# into one dash, with no dash at either end. Text with no letter or digit has an empty slug.
slug_of() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed -e 's/^-*//' -e 's/-*$//'
}
