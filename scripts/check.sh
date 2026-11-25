#!/usr/bin/env bash
# Run the plugin's offline checks: node unit/repo tests, then a QML syntax
# pass with qmllint when one is installed. No network, no writes.
set -euo pipefail
cd "$(dirname "$0")/.."

node --test 'tests/*.test.mjs'

lint=""
for candidate in qmllint qmllint6 /usr/lib/qt6/bin/qmllint pyside6-qmllint; do
  if command -v "$candidate" >/dev/null 2>&1; then
    lint="$candidate"
    break
  fi
done

if [[ -z $lint ]]; then
  echo "qmllint not found; skipped QML syntax check"
  exit 0
fi

# Omarchy's qs.* imports only resolve inside omarchy-shell, so unresolved-type
# warnings are expected here. Only syntax errors fail the check.
status=0
while IFS= read -r -d '' file; do
  if "$lint" "$file" 2>&1 | grep -F "[syntax]"; then
    echo "syntax error in $file"
    status=1
  fi
done < <(git ls-files -z -- '*.qml' 2>/dev/null || find . -name '*.qml' -not -path './.git/*' -print0)
[[ $status -eq 0 ]] && echo "qmllint: no syntax errors"
exit "$status"
