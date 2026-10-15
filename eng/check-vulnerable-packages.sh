#!/usr/bin/env bash
# Fails when any NuGet package (direct or transitive) has a High or Critical advisory.
# Low and Moderate advisories are reported but do not fail.
#
# Usage: eng/check-vulnerable-packages.sh [report.json]
#   With no argument, runs `dotnet list package --no-restore --vulnerable --include-transitive
#   --format json`; restore first (in CI with -p:NuGetAudit=false, so a High advisory does not
#   fail the restore before this script can report it). With an argument, reads that JSON report.
set -euo pipefail

if [[ $# -ge 1 ]]; then
  report="$(cat "$1")"
else
  report="$(dotnet list package --no-restore --vulnerable --include-transitive --format json --output-version 1)"
fi

# The JSON report lists problems (e.g. a source that could not be queried) at the top level and
# per project. Treat them as failures: an audit that did not run is not a pass.
problems="$(jq -r '[.problems[]?, .projects[]?.problems[]?] | .[] | "\(.level): \(.text)"' <<<"$report")"
if [[ -n "$problems" ]]; then
  echo "::error::dotnet list package reported problems:"
  echo "$problems"
  exit 1
fi

# One TSV row per (project, framework, package, advisory).
rows="$(jq -r '
  .projects[]? as $p
  | $p.frameworks[]? as $f
  | (($f.topLevelPackages // []) | map(. + {kind: "direct"}))
    + (($f.transitivePackages // []) | map(. + {kind: "transitive"}))
  | .[]
  | . as $pkg
  | $pkg.vulnerabilities[]?
  | [.severity, $pkg.id, $pkg.resolvedVersion, $pkg.kind, ($p.path | split("/") | last), $f.framework, .advisoryurl]
  | @tsv' <<<"$report")"

summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
blocking=0
total=0

{
  echo "## Vulnerable NuGet packages"
  echo
} >>"$summary"

if [[ -z "$rows" ]]; then
  echo "No vulnerable packages found."
  echo "No vulnerable packages found." >>"$summary"
  exit 0
fi

{
  echo "| Severity | Package | Version | Kind | Project | Framework | Advisory |"
  echo "| --- | --- | --- | --- | --- | --- | --- |"
} >>"$summary"

while IFS=$'\t' read -r severity id version kind project framework url; do
  total=$((total + 1))
  line="${severity} ${id} ${version} (${kind}) in ${project} [${framework}] ${url}"
  case "${severity,,}" in
    high | critical)
      blocking=$((blocking + 1))
      echo "::error title=Vulnerable package::${line}"
      ;;
    *)
      echo "::warning title=Vulnerable package::${line}"
      ;;
  esac
  echo "| ${severity} | ${id} | ${version} | ${kind} | ${project} | ${framework} | ${url} |" >>"$summary"
done <<<"$rows"

echo "Found ${total} advisory finding(s); ${blocking} High/Critical."
if [[ $blocking -gt 0 ]]; then
  exit 1
fi
