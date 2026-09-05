#!/usr/bin/env bash
set -euo pipefail

workplace="${DEV_WORKPLACE:-$HOME/Workplace}"
repo="$workplace/payments-demo"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

prepare_repository() {
  if [ -d "$repo/.git" ]; then
    return
  fi
  [ ! -e "$repo" ] || die "Demo path already exists and is not a Git repository: $repo"

  mkdir -p "$repo/src"
  git init -q -b main "$repo"
  git -C "$repo" config user.name 'Dev Harness Demo'
  git -C "$repo" config user.email 'demo@localhost'
  git -C "$repo" config commit.gpgsign false

  printf '%s\n' \
    '# Payments demo' \
    '' \
    'A sample repository for the Dev Harness Docker demo.' > "$repo/README.md"
  printf '%s\n' \
    'public final class PaymentService {' \
    '    public String authorize() {' \
    '        return "approved";' \
    '    }' \
    '}' > "$repo/src/PaymentService.java"

  git -C "$repo" add README.md src/PaymentService.java
  git -C "$repo" commit -q --no-verify -m 'Create payment service'

  printf '%s\n' \
    'public final class PaymentService {' \
    '    public String authorize(int attempt) {' \
    '        // TODO: replace this with a bounded retry policy.' \
    '        return attempt > 1 ? "approved" : "retry";' \
    '    }' \
    '}' > "$repo/src/PaymentService.java"
  mkdir -p "$repo/notes"
  printf '%s\n' \
    '# Retry plan' \
    '' \
    '- Add a maximum attempt count.' \
    '- Review timeout handling.' > "$repo/notes/retry-plan.md"
}

show_welcome() {
  printf '%s\n' \
    '' \
    'Dev Harness demo' \
    "Repository: $repo" \
    '' \
    'Commands:' \
    '  gtask                 open the searchable command palette' \
    '  gtask open            pick and open a repository file' \
    '  gtask changed         pick one of the prepared changes' \
    '  gtask search -- retry search workplace code and notes' \
    '  gtask semantic -- retry search workplace code by meaning' \
    '  gtask index           initialize the workplace semantic index' \
    '  gtask changes         summarize the prepared changes' \
    '  gtask context         select files for AI context' \
    '  why                   explain this repository context' \
    '' \
    'Run exit to stop. Docker --rm removes the container.' \
    'Not connected: VS Code, Obsidian, Docker-in-Docker, external AI CLIs, Ollama.' \
    ''
}

prepare_repository
if command -v grepai >/dev/null 2>&1; then
  (cd "$workplace" && grepai init --yes --provider ollama --backend gob)
fi
show_welcome

case "${1:-}" in
  --prepare-only) exit 0 ;;
  '') ;;
  *) die 'This image accepts no command arguments; run it interactively with docker run --rm -it.' ;;
esac

cd "$repo"
exec bash -i
