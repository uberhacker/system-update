#!/usr/bin/env bash
# lib/tools/pip.sh - Python CLI tools: pipx upgrade-all, pip itself, aws cli.
#
# On PEP 668 ("externally managed") distros `pip install --user` is refused
# and would be wrong anyway; pipx (and uv, see uv.sh) own user-level tools
# there. aws cli v2 is not a pip package: it is skipped with a note unless
# v1 is installed through pipx or a plain user pip on a non-PEP-668 python.

tool_pip_detect() {
  user_bin pipx || user_bin pip || user_bin pip3 || user_bin aws
}

# pip_externally_managed: does the default python3 carry EXTERNALLY-MANAGED?
pip_externally_managed() {
  has_cmd python3 || return 1
  python3 -c 'import os, sys, sysconfig; sys.exit(0 if os.path.exists(os.path.join(sysconfig.get_path("stdlib"), "EXTERNALLY-MANAGED")) else 1)' 2>/dev/null
}

tool_pip_update() {
  local pip aws ver notes=() failed=0 changed=0 log pep668=0
  log=$(tmp_file) || return 1
  pip_externally_managed && pep668=1

  if has_cmd pipx; then
    if [ "$SU_DRY_RUN" = 1 ]; then
      notes+=("would run pipx upgrade-all")
    elif run_capture "$log" run_user pipx upgrade-all; then
      if grep -qiE 'upgraded package' "$log"; then changed=1; notes+=("pipx: packages upgraded"); else notes+=("pipx: all up to date"); fi
    else
      notes+=("pipx upgrade-all failed"); failed=1
    fi
  fi

  pip=$(user_bin pip || user_bin pip3 || true)
  if [ -n "$pip" ]; then
    case "$pip" in
      "$SU_USER_HOME"/.local/bin/pip*)
        if [ "$pep668" = 1 ]; then
          notes+=("pip: externally managed python (PEP 668), not upgrading pip itself")
        elif [ "$SU_DRY_RUN" = 1 ]; then
          notes+=("would run pip install --user -U pip")
        elif run_capture "$log" run_user "$pip" install --user -U pip; then
          grep -q 'Successfully installed' "$log" && changed=1
          notes+=("pip: ok")
        else
          notes+=("pip self-upgrade failed"); failed=1
        fi ;;
      *) notes+=("pip: system pip at $pip is managed by the package manager") ;;
    esac
  fi

  aws=$(user_bin aws || true)
  if [ -n "$aws" ]; then
    ver=$(tool_probe "$aws" --version | head -n1)
    case "$ver" in
      aws-cli/2.*)
        notes+=("aws: v2 is not a pip package; update it with its installer or your package manager") ;;
      aws-cli/1.*)
        if has_cmd pipx && run_user pipx list --short 2>/dev/null | grep -q '^awscli '; then
          notes+=("aws: v1 via pipx (covered by upgrade-all)")
        elif [ "$aws" = "$SU_USER_HOME/.local/bin/aws" ] && [ -n "$pip" ] && [ "$pep668" != 1 ]; then
          if [ "$SU_DRY_RUN" = 1 ]; then
            notes+=("would run pip install --user -U awscli")
          elif run_capture "$log" run_user "$pip" install --user -U awscli; then
            grep -q 'Successfully installed' "$log" && changed=1
            notes+=("aws: v1 upgraded via pip")
          else
            notes+=("aws v1 pip upgrade failed"); failed=1
          fi
        else
          notes+=("aws: v1 not installed for the user via pip/pipx; skipped")
        fi ;;
      *) notes+=("aws: unrecognised version output; skipped") ;;
    esac
  fi

  [ ${#notes[@]} -gt 0 ] || { step_skip "nothing to do"; return 0; }
  if [ "$SU_DRY_RUN" = 1 ]; then step_dry "$(join_by '; ' "${notes[@]}")"
  elif [ "$failed" = 1 ]; then step_fail "$(join_by '; ' "${notes[@]}")"
  elif [ "$changed" = 1 ]; then step_updated "$(join_by '; ' "${notes[@]}")"
  else step_ok "$(join_by '; ' "${notes[@]}")"
  fi
}
