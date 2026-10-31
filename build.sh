#!/usr/bin/env bash
# build.sh - make the single-file build of system-update.
#
#   ./build.sh [OUTPUT]     default OUTPUT: dist/system-update
#
# The entry point (bin/system-update) is copied with the block between its
# @@BUNDLE-MODULES-BEGIN@@ / -END@@ markers replaced by the contents of the
# modules it sources, in the same order, followed by every lib/tools module.
# The entry point's `SU_BUNDLED=0` line becomes `SU_BUNDLED=1`; the version,
# the git commit and the list of tools are recorded at the top
# (SU_BUNDLE_VERSION, SU_BUNDLE_COMMIT, SU_BUNDLED_TOOLS) and the bash
# completion script is embedded for `--completion bash`. The result
# is plain bash: nothing is compiled, it needs the same bash 4.4 and
# coreutils as the multi-file version, and it is checked with bash -n.
set -euo pipefail

root=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
out="${1:-$root/dist/system-update}"
entry="$root/bin/system-update"

if ! grep -q '^# @@BUNDLE-MODULES-BEGIN@@$' "$entry" || ! grep -q '^# @@BUNDLE-MODULES-END@@$' "$entry" \
   || ! grep -q '^SU_BUNDLED=0' "$entry"; then
  echo "build.sh: bundle markers not found in $entry" >&2
  exit 1
fi
# The modules the entry point sources, in its order.
# shellcheck disable=SC2016  # $SU_ROOT is matched literally
mapfile -t modules < <(sed -n 's|^source "\$SU_ROOT/\(lib/[^"]*\.sh\)"$|\1|p' "$entry")
[ ${#modules[@]} -gt 0 ] || { echo "build.sh: no modules found in $entry" >&2; exit 1; }

version=$(tr -d '[:space:]' < "$root/VERSION")
commit=unknown
if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
  commit=$(git -C "$root" rev-parse --short HEAD)
  # Modified or untracked files under the bundled paths make it a -dirty build.
  [ -z "$(git -C "$root" status --porcelain -- bin lib completions VERSION 2>/dev/null)" ] || commit="$commit-dirty"
fi
tools=()
for f in "$root"/lib/tools/*.sh; do
  f="${f##*/}"
  tools+=("${f%.sh}")
done

# module FILE: a module's contents under a banner, without its shebang.
module() {
  printf '\n# ==== %s ====\n' "${1#"$root"/}"
  sed '1{/^#!/d}' "$1"
}

mkdir -p "$(dirname "$out")"
tmp=$(mktemp "$(dirname "$out")/.system-update.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT
{
  inside=0
  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    if [ "$lineno" = 1 ]; then
      printf '%s\n' "$line"
      cat <<EOF
#
# Single-file build of system-update $version (git $commit), made by
# build.sh from https://github.com/bradvrudney/system-update. Do not edit:
# change the modules in lib/ and rebuild.
SU_BUNDLE_VERSION='$version'
SU_BUNDLE_COMMIT='$commit'
SU_BUNDLED_TOOLS=(${tools[*]})
EOF
      continue
    fi
    case "$line" in
      'SU_BUNDLED=0'*)
        printf 'SU_BUNDLED=1\n'
        continue ;;
      '# @@BUNDLE-MODULES-BEGIN@@')
        inside=1
        for m in "${modules[@]}"; do
          module "$root/$m"
        done
        for t in "${tools[@]}"; do
          module "$root/lib/tools/$t.sh"
        done
        printf '\n# ==== completions/system-update.bash (for --completion bash) ====\n'
        printf "su_completion_script() {\n  cat <<'SU_COMPLETION_EOF'\n"
        cat "$root/completions/system-update.bash"
        printf 'SU_COMPLETION_EOF\n}\n'
        printf '# ==== end of modules ====\n'
        continue ;;
      '# @@BUNDLE-MODULES-END@@')
        inside=0
        continue ;;
    esac
    [ "$inside" = 1 ] || printf '%s\n' "$line"
  done < "$entry"
} > "$tmp"

bash -n "$tmp" || { echo "build.sh: the result does not parse" >&2; exit 1; }
chmod 0755 "$tmp"
mv -f -- "$tmp" "$out"
trap - EXIT
printf 'built %s (%s, git %s, %s tools, %s lines)\n' "$out" "$version" "$commit" "${#tools[@]}" "$(wc -l < "$out")"
