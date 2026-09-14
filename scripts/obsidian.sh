#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

obsidian_bin="$(obsidian_executable)" || die "Obsidian CLI is unavailable. Enable it in Obsidian Settings → General."
mode="${1:-day}"
shift || true
project="$(project_slug)"
created=""
git_branch=""
git_commit=""
todo_base_path="TODO/TODO.base"

iso_now() {
  local timestamp offset
  timestamp="$(date '+%Y-%m-%dT%H:%M:%S')"
  offset="$(date '+%z')"
  case "$offset" in
    [+-][0-9][0-9][0-9][0-9])
      printf '%s%s:%s\n' "$timestamp" "${offset%??}" "${offset#???}"
      ;;
    *) printf '%s%s\n' "$timestamp" "$offset" ;;
  esac
}

load_git_context() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch="$(git branch --show-current)"
    git_commit="$(git rev-parse --short HEAD 2>/dev/null || true)"
  fi
}

require_todo_project() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "Run this command inside a project Git repository. Use 'gtask todos' for the global list."
  project="$(project_slug)"
  load_git_context
}

entry_context() {
  local project_link="[[Projects/$project]]"
  if [ -n "$git_commit" ]; then
    printf '%s · `%s` · `%s` #project/%s' "$project_link" "${git_branch:-detached}" "$git_commit" "$project"
  else
    printf '%s #project/%s' "$project_link" "$project"
  fi
}

obs() {
  if [ -n "${DEV_OBSIDIAN_VAULT:-}" ]; then
    "$obsidian_bin" "vault=$DEV_OBSIDIAN_VAULT" "$@"
  else
    "$obsidian_bin" "$@"
  fi
}

set_note_properties() {
  local path="$1" type="$2"
  created="${created:-$(iso_now)}"
  obs property:set name=type value="$type" type=text path="$path" >/dev/null
  obs property:set name=created value="$created" type=datetime path="$path" >/dev/null
  obs property:set name=project value="$project" type=text path="$path" >/dev/null
  obs property:set name=tags value="$type,project/$project" type=list path="$path" >/dev/null
  if [ -n "$git_commit" ]; then
    obs property:set name=branch value="${git_branch:-detached}" type=text path="$path" >/dev/null
    obs property:set name=commit value="$git_commit" type=text path="$path" >/dev/null
  fi
}

ensure_note() {
  local path="$1" title="$2" type="$3"
  if ! obs file path="$path" >/dev/null 2>&1; then
    obs create path="$path" content="# $title" >/dev/null
    set_note_properties "$path" "$type"
    obs append path="$path" content="Project: [[Projects/$project]]" >/dev/null
  fi
}

todo_base_content() {
  printf '%s\n' 'filters:
  and:
    - file.inFolder("TODO")
    - file.ext == "md"
    - type == "todo"
properties:
  file.path:
    displayName: Path
  title:
    displayName: Title
  project:
    displayName: Project
  priority:
    displayName: Priority
  status:
    displayName: Status
  created:
    displayName: Created
  completed:
    displayName: Completed
  tags:
    displayName: Tags
views:
  - type: table
    name: Open
    filters:
      and:
        - status == "open"
    order:
      - file.path
      - title
      - project
      - priority
      - status
      - created
      - completed
      - tags
    sort:
      - property: priority
        direction: ASC
      - property: created
        direction: DESC
  - type: table
    name: Done
    filters:
      and:
        - status == "done"
    order:
      - file.path
      - title
      - project
      - priority
      - status
      - created
      - completed
      - tags
    sort:
      - property: completed
        direction: DESC
  - type: table
    name: By project
    filters:
      and:
        - status == "open"
    groupBy:
      property: project
      direction: ASC
    order:
      - file.path
      - title
      - project
      - priority
      - status
      - created
      - completed
      - tags
    sort:
      - property: priority
        direction: ASC
      - property: created
        direction: DESC
  - type: table
    name: By priority
    filters:
      and:
        - status == "open"
    groupBy:
      property: priority
      direction: ASC
    order:
      - file.path
      - title
      - project
      - priority
      - status
      - created
      - completed
      - tags
    sort:
      - property: project
        direction: ASC
      - property: created
        direction: DESC'
}

ensure_todo_base() {
  if ! obs file path="$todo_base_path" >/dev/null 2>&1; then
    obs create path="$todo_base_path" content="$(todo_base_content)" >/dev/null
    printf 'Created Obsidian Base: %s\n' "$todo_base_path"
  fi
}

todo_base_exists() {
  obs file path="$todo_base_path" >/dev/null 2>&1
}

parse_todo_priority() {
  todo_text="$1"
  priority="${DEV_TODO_DEFAULT_PRIORITY:-p2}"
  priority_explicit=false
  first_token="${todo_text%% *}"
  case "$first_token" in
    p0|--p0|--critical|--urgent) priority=p0; priority_explicit=true ;;
    p1|--p1|--high) priority=p1; priority_explicit=true ;;
    p2|--p2|--medium|--normal) priority=p2; priority_explicit=true ;;
    p3|--p3|--low) priority=p3; priority_explicit=true ;;
  esac
  case "$priority" in
    p0) priority_label='P0' ;;
    p1) priority_label='P1' ;;
    p2) priority_label='P2' ;;
    p3) priority_label='P3' ;;
    *) die "DEV_TODO_DEFAULT_PRIORITY must be one of: p0, p1, p2, p3." ;;
  esac
  if [ "$priority_explicit" = true ]; then
    todo_text="${todo_text#"$first_token"}"
    todo_text="${todo_text# }"
  fi
}

is_todo_filter_input() {
  local input="$1" token
  local tokens=()
  [ -z "$input" ] && return 0
  read -r -a tokens <<< "$input"
  for token in "${tokens[@]}"; do
    case "$token" in
      p0|p1|p2|p3|--p0|--p1|--p2|--p3|open|--open|'done'|'--done') ;;
      *) return 1 ;;
    esac
  done
}

parse_list_filters() {
  local input="$1" token
  local tokens=()
  list_status=open
  list_priority=""
  read -r -a tokens <<< "$input"
  for token in "${tokens[@]}"; do
    case "$token" in
      open|--open) list_status=open ;;
      'done'|'--done') list_status='done' ;;
      p0|--p0) list_priority=p0 ;;
      p1|--p1) list_priority=p1 ;;
      p2|--p2) list_priority=p2 ;;
      p3|--p3) list_priority=p3 ;;
      *) die "Unknown TODO filter: $token. Use open, done, or p0 through p3." ;;
    esac
  done
}

normalize_todo_title() {
  printf '%s' "$1" \
    | tr '\r\n\t' '   ' \
    | sed -E 's#[[:space:]]+# #g; s#^ +| +$##g'
}

unique_todo_path() {
  local title_slug="$1" stem candidate suffix
  stem="TODO/$(date '+%Y/%m/%Y%m%d-%H%M%S')-$title_slug"
  candidate="$stem.md"
  suffix=2
  while obs file path="$candidate" >/dev/null 2>&1; do
    candidate="$stem-$suffix.md"
    suffix=$((suffix + 1))
  done
  printf '%s\n' "$candidate"
}

create_todo_note() {
  local title="$1" title_slug path project_link
  title="$(normalize_todo_title "$title")"
  [ -n "$title" ] || die "TODO title cannot be empty."
  title_slug="$(slugify "$title" | cut -c1-80)"
  [ -n "$title_slug" ] || title_slug=todo
  path="$(unique_todo_path "$title_slug")"
  created="$(iso_now)"
  project_link="[[Projects/$project]]"

  ensure_todo_base
  obs create path="$path" content="# $title" >/dev/null
  obs property:set name=type value=todo type=text path="$path" >/dev/null
  obs property:set name=title value="$title" type=text path="$path" >/dev/null
  obs property:set name=status value=open type=text path="$path" >/dev/null
  obs property:set name=priority value="$priority" type=text path="$path" >/dev/null
  obs property:set name=project value="$project" type=text path="$path" >/dev/null
  obs property:set name=created value="$created" type=datetime path="$path" >/dev/null
  if [ -n "$git_commit" ]; then
    obs property:set name=branch value="${git_branch:-detached}" type=text path="$path" >/dev/null
    obs property:set name=commit value="$git_commit" type=text path="$path" >/dev/null
    obs property:set name=project_link value="$project_link" type=text path="$path" >/dev/null
  fi
  printf 'Created %s TODO: %s\n' "$priority_label" "$path"
}

parse_base_tsv() {
  awk -F '\t' '
    BEGIN { OFS="\t" }
    NR == 1 {
      for (i = 1; i <= NF; i++) {
        key = tolower($i)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
        if (key == "path" || key == "file.path") path_col=i
        else if (key == "title") title_col=i
        else if (key == "project") project_col=i
        else if (key == "priority") priority_col=i
        else if (key == "status") status_col=i
        else if (key == "created") created_col=i
        else if (key == "completed") completed_col=i
      }
      if (!path_col || !title_col || !project_col || !priority_col || !status_col || !created_col || !completed_col) {
        print "Unexpected TODO.base TSV columns." > "/dev/stderr"
        exit 64
      }
      next
    }
    NF {
      print $path_col, $title_col, $project_col, $priority_col, $status_col, $created_col, $completed_col
    }
  '
}

query_todo_rows() {
  local status="$1" view raw rows
  if ! todo_base_exists; then
    return 0
  fi
  if [ "$status" = 'done' ]; then view=Done; else view=Open; fi
  if ! raw="$(obs base:query path="$todo_base_path" view="$view" format=tsv)"; then
    die "Could not query $todo_base_path. Enable the Obsidian Bases core plugin and verify the Base file."
  fi
  if ! rows="$(printf '%s\n' "$raw" | tr -d '\r' | parse_base_tsv)"; then
    die "Could not parse the TODO Base query. Open $todo_base_path in Obsidian and verify its columns."
  fi
  printf '%s' "$rows"
}

filter_and_sort_todo_rows() {
  local rows="$1" project_filter="$2" priority_filter="$3" status="$4"
  [ -n "$rows" ] || return 0
  if [ "$status" = 'done' ]; then
    printf '%s\n' "$rows" \
      | awk -F '\t' -v OFS='\t' -v project="$project_filter" -v priority="$priority_filter" \
          '(!project || $3 == project) && (!priority || $4 == priority) { print }' \
      | sort -t $'\t' -k7,7r -k6,6r
  else
    printf '%s\n' "$rows" \
      | awk -F '\t' -v OFS='\t' -v project="$project_filter" -v priority="$priority_filter" '
          (!project || $3 == project) && (!priority || $4 == priority) {
            rank=9
            if ($4 == "p0") rank=0
            else if ($4 == "p1") rank=1
            else if ($4 == "p2") rank=2
            else if ($4 == "p3") rank=3
            print rank, $0
          }' \
      | sort -t $'\t' -k1,1n -k7,7r \
      | cut -f2-
  fi
}

todo_rows() {
  local scope="$1" input="$2" project_filter="" rows
  parse_list_filters "$input"
  if [ "$scope" = project ]; then
    require_todo_project
    project_filter="$project"
  fi
  rows="$(query_todo_rows "$list_status")"
  filter_and_sort_todo_rows "$rows" "$project_filter" "$list_priority" "$list_status"
}

print_todo_rows() {
  local rows="$1" path title item_project item_priority label
  if [ -z "$rows" ]; then
    printf 'No matching TODOs.\n'
    return
  fi
  while IFS=$'\t' read -r path title item_project item_priority _ _ _; do
    label="$(printf '%s' "$item_priority" | tr '[:lower:]' '[:upper:]')"
    printf '%-2s  [%-18s] %s  · %s\n' "$label" "$item_project" "$title" "$path"
  done <<<"$rows"
}

list_todo_notes() {
  local scope="$1" input="$2" rows
  rows="$(todo_rows "$scope" "$input")"
  print_todo_rows "$rows"
}

todo_preview_command() {
  local command
  printf -v command '%q' "$obsidian_bin"
  if [ -n "${DEV_OBSIDIAN_VAULT:-}" ]; then
    printf -v command '%s %q' "$command" "vault=$DEV_OBSIDIAN_VAULT"
  fi
  printf '%s read path={1}' "$command"
}

select_todo_note() {
  local status="$1" input="$2" rows prompt selection
  need fzf
  parse_list_filters "$input"
  list_status="$status"
  rows="$(query_todo_rows "$status")"
  rows="$(filter_and_sort_todo_rows "$rows" "" "$list_priority" "$status")"
  if [ -z "$rows" ]; then
    printf 'No matching %s TODOs.\n' "$status"
    return 1
  fi
  if [ "$status" = 'done' ]; then prompt='reopen todo > '; else prompt='complete todo > '; fi
  selection="$(printf '%s\n' "$rows" | fzf \
    --delimiter=$'\t' \
    --with-nth=4,3,2,6 \
    --nth=2,3,4 \
    --prompt="$prompt" \
    --header='priority · project · title · created' \
    --preview="$(todo_preview_command)" \
    --preview-window='right,60%,wrap')" || return 1
  printf '%s\n' "$selection"
}

complete_todo_note() {
  local input="$1" selection path title completed_at
  selection="$(select_todo_note open "$input")" || {
    [ -n "$selection" ] && printf '%s\n' "$selection"
    exit 0
  }
  IFS=$'\t' read -r path title _ <<<"$selection"
  completed_at="$(iso_now)"
  obs property:set name=status value=done type=text path="$path" >/dev/null
  obs property:set name=completed value="$completed_at" type=datetime path="$path" >/dev/null
  printf 'Completed: %s\n' "$title"
}

reopen_todo_note() {
  local input="$1" selection path title
  selection="$(select_todo_note 'done' "$input")" || {
    [ -n "$selection" ] && printf '%s\n' "$selection"
    exit 0
  }
  IFS=$'\t' read -r path title _ <<<"$selection"
  obs property:set name=status value=open type=text path="$path" >/dev/null
  obs property:remove name=completed path="$path" >/dev/null
  printf 'Reopened: %s\n' "$title"
}

print_todos_tsv() {
  local scope="${1:-}" status="${2:-}" priority="${3:-}"
  [ "$#" -ge 2 ] && [ "$#" -le 3 ] \
    || die "Use 'obsidian.sh todos-tsv <project|all> <open|done> [p0|p1|p2|p3]'."
  case "$scope" in
    project|all) ;;
    *) die "Use 'obsidian.sh todos-tsv <project|all> <open|done> [p0|p1|p2|p3]'." ;;
  esac
  case "$status" in
    open|done) ;;
    *) die "Use 'obsidian.sh todos-tsv <project|all> <open|done> [p0|p1|p2|p3]'." ;;
  esac
  case "$priority" in
    ''|p0|p1|p2|p3) ;;
    *) die "Use 'obsidian.sh todos-tsv <project|all> <open|done> [p0|p1|p2|p3]'." ;;
  esac
  todo_rows "$scope" "$status${priority:+ $priority}"
}

append_exact_daily() {
  [ "$#" -eq 1 ] || die "Use 'obsidian.sh day-append <markdown>'."
  obs daily:append content="$1"
}

case "$mode" in
  note)
    load_git_context
    created="$(iso_now)"
    title="${DEV_HARNESS_INPUT:-$*}"
    if [ -z "$title" ]; then
      read -r -p 'Note title: ' title
    fi
    [ -n "$title" ] || exit 0
    safe_title="$(printf '%s' "$title" | sed -E 's#[/\\:*?"<>|]+#-#g; s#[[:space:]]+# #g; s#^ +| +$##g')"
    path="Notes/$(date '+%Y-%m-%d-%H%M') $safe_title.md"
    ensure_note "$path" "$title" note
    obs open path="$path"
    ;;
  day)
    load_git_context
    text="${DEV_HARNESS_INPUT:-$*}"
    if [ -z "$text" ]; then
      obs daily
    else
      obs daily:append content="- $(date '+%H:%M') $text — $(entry_context)" open
    fi
    ;;
  week)
    load_git_context
    created="$(iso_now)"
    text="${DEV_HARNESS_INPUT:-$*}"
    week_id="$(date '+%G-W%V')"
    path="Weekly/$week_id.md"
    ensure_note "$path" "$week_id" weekly
    if [ -n "$text" ]; then
      obs append path="$path" content="- $text — $(entry_context)"
    fi
    obs open path="$path"
    ;;
  todo)
    text="${DEV_HARNESS_INPUT:-$*}"
    if is_todo_filter_input "$text"; then
      list_todo_notes project "$text"
    else
      require_todo_project
      parse_todo_priority "$text"
      create_todo_note "$todo_text"
    fi
    ;;
  todos)
    text="${DEV_HARNESS_INPUT:-$*}"
    is_todo_filter_input "$text" || die "Use 'gtask todos -- [open|done] [p0..p3]'."
    list_todo_notes all "$text"
    ;;
  done)
    text="${DEV_HARNESS_INPUT:-$*}"
    is_todo_filter_input "$text" || die "Use 'gtask done -- [p0..p3]'."
    complete_todo_note "$text"
    ;;
  reopen)
    text="${DEV_HARNESS_INPUT:-$*}"
    is_todo_filter_input "$text" || die "Use 'gtask reopen -- [p0..p3]'."
    reopen_todo_note "$text"
    ;;
  todos-tsv)
    print_todos_tsv "$@"
    ;;
  day-append)
    append_exact_daily "$@"
    ;;
  *) die "Unknown Obsidian mode: $mode" ;;
esac
