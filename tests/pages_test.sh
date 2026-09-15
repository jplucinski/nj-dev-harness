#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$test_dir/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [ -f "$root/$1" ] || fail "missing $1"
}

assert_contains() {
  local file="$1" expected="$2"
  grep -Fq -- "$expected" "$root/$file" || fail "$file does not contain: $expected"
}

assert_not_contains() {
  local file="$1" unexpected="$2"
  if grep -Fiq -- "$unexpected" "$root/$file"; then
    fail "$file unexpectedly contains: $unexpected"
  fi
}

assert_file docs/site/index.html
assert_file docs/site/tutorial.html
assert_file docs/site/styles.css
assert_file docs/site/app.js
assert_file .github/workflows/pages.yml

for anchor in find "do" remember install security; do
  assert_contains docs/site/index.html "id=\"$anchor\""
done

assert_contains docs/site/index.html 'Find · Do · Remember'
assert_contains docs/site/index.html 'gtask review -- --all'
assert_contains docs/site/index.html 'Notes/'
assert_contains docs/site/index.html 'Daily/'
assert_contains docs/site/index.html 'Weekly/'
assert_contains docs/site/index.html 'TODO/'
assert_contains docs/site/index.html 'href="tutorial.html"'

for anchor in requirements install configure find "do" remember todo extend troubleshooting; do
  assert_contains docs/site/tutorial.html "id=\"$anchor\""
done

assert_contains docs/site/tutorial.html 'href="index.html"'
assert_contains docs/site/tutorial.html 'gtask review -- --all'
assert_contains docs/site/tutorial.html 'DEV_WORKPLACE'
assert_contains docs/site/tutorial.html 'gtask todo -- p1'
assert_contains docs/site/tutorial.html 'gtask extend'
assert_contains docs/site/app.js 'if (lines)'

assert_not_contains docs/site/index.html 'google-analytics'
assert_not_contains docs/site/index.html 'googletagmanager'
assert_not_contains docs/site/index.html '<script src="http'
assert_not_contains docs/site/index.html '<link rel="stylesheet" href="http'
assert_not_contains docs/site/index.html 'github.com/OWNER/'
assert_not_contains docs/site/tutorial.html 'github.com/OWNER/'

for page in index.html tutorial.html; do
  while IFS= read -r href; do
    case "$href" in
      http*|mailto:*|'#'*|README.md|PRD.md|SECURITY.md|CONTRIBUTING.md|'') continue ;;
    esac
    target="${href%%#*}"
    target="${target%%\?*}"
    [ -f "$root/docs/site/$target" ] || fail "$page has a missing local target: $href"
  done < <(grep -Eo 'href="[^"]+"' "$root/docs/site/$page" | sed 's/^href="//; s/"$//')
done

workflow='.github/workflows/pages.yml'
assert_contains "$workflow" 'contents: read'
assert_contains "$workflow" 'pages: write'
assert_contains "$workflow" 'id-token: write'
assert_contains "$workflow" 'name: github-pages'
assert_contains "$workflow" 'persist-credentials: false'
assert_contains "$workflow" 'actions/configure-pages@'
assert_contains "$workflow" 'actions/upload-pages-artifact@'
assert_contains "$workflow" 'actions/deploy-pages@'

if grep -Eq 'uses: actions/(checkout|configure-pages|upload-pages-artifact|deploy-pages)@v[0-9]' "$root/$workflow"; then
  fail 'Pages workflow uses a mutable major-version tag'
fi

while IFS= read -r ref; do
  sha="${ref##*@}"
  case "$sha" in
    *[!0-9a-f]*|'') fail "action is not pinned to a hexadecimal SHA: $ref" ;;
  esac
  [ "${#sha}" -eq 40 ] || fail "action SHA is not 40 characters: $ref"
done < <(grep -Eo 'actions/(checkout|configure-pages|upload-pages-artifact|deploy-pages)@[0-9a-f]+' "$root/$workflow")

if grep -RIEq 'TBD|YOUR[_ -]?(USER|ORG|OWNER)|example\.com' \
  "$root/docs/site" "$root/$workflow"; then
  fail 'Pages files contain an unresolved placeholder'
fi

printf 'PASS: GitHub Pages site and deployment contract\n'
