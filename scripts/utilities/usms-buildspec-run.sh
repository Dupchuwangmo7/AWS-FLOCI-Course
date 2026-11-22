#!/usr/bin/env bash
# usms-buildspec-run.sh — run a CodeBuild buildspec.yml locally, phase by phase.
#
# Usage: scripts/utilities/usms-buildspec-run.sh <app-dir> [buildspec-file]
#
# Reads <app-dir>/buildspec.yml (PyYAML if installed, otherwise a built-in
# minimal parser for the subset CodeBuild buildspecs use), generates one bash
# script that exports env.variables (unless already set in the environment, as a
# CodeBuild project variable would be) and runs install -> pre_build -> build ->
# post_build in order inside <app-dir>, and stops at the first failing command.
#
# Differences from CodeBuild: no CODEBUILD_* variables (build-metadata.json
# therefore says buildId "local"), no artifact upload, and a failure stops the
# run immediately (CodeBuild still runs post_build after a failed build phase).
# Works with macOS bash 3.2.
set -uo pipefail

APP_DIR="${1:?usage: usms-buildspec-run.sh <app-dir> [buildspec-file]}"
SPEC="${2:-buildspec.yml}"
[ -d "$APP_DIR" ] || { echo "ERROR: no such directory: $APP_DIR" >&2; exit 2; }
APP_DIR="$(cd "$APP_DIR" && pwd)"
[ -f "$APP_DIR/$SPEC" ] || { echo "ERROR: $APP_DIR/$SPEC not found" >&2; exit 2; }
command -v python3 >/dev/null || { echo "ERROR: python3 is required" >&2; exit 2; }

GEN="$(mktemp "${TMPDIR:-/tmp}/usms-buildspec.XXXXXX")"
trap 'rm -f "$GEN"' EXIT

python3 - "$APP_DIR/$SPEC" > "$GEN" <<'PY' || { echo "ERROR: could not parse $SPEC" >&2; exit 2; }
import sys, shlex

PHASES = ["install", "pre_build", "build", "post_build"]
text = open(sys.argv[1]).read()

def minimal_parse(text):
    """Parse the buildspec subset: env.variables, phases.<p>.commands, artifacts."""
    lines = text.splitlines()
    spec = {"env": {"variables": {}}, "phases": {}, "artifacts": {}}
    path = []          # stack of (indent, key)
    i = 0
    def unq(v):
        v = v.strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
            return v[1:-1]
        return v
    while i < len(lines):
        raw = lines[i]
        s = raw.strip()
        if not s or s.startswith("#"):
            i += 1; continue
        ind = len(raw) - len(raw.lstrip(" "))
        while path and path[-1][0] >= ind:
            path.pop()
        keys = [k for _, k in path]
        if s.startswith("- "):
            item = s[2:]
            if item.strip() in ("|", "|-", ">", ">-"):
                block, j = [], i + 1
                bind = None
                while j < len(lines):
                    r = lines[j]
                    if r.strip() == "":
                        block.append(""); j += 1; continue
                    ri = len(r) - len(r.lstrip(" "))
                    if ri <= ind: break
                    if bind is None: bind = ri
                    block.append(r[bind:]); j += 1
                while block and block[-1] == "": block.pop()
                item = "\n".join(block) if item.strip().startswith("|") else " ".join(block)
                i = j
            else:
                item = unq(item); i += 1
            if len(keys) >= 3 and keys[0] == "phases" and keys[2] == "commands":
                spec["phases"].setdefault(keys[1], {}).setdefault("commands", []).append(item)
            elif keys[:2] == ["artifacts", "files"]:
                spec["artifacts"].setdefault("files", []).append(item)
            continue
        k, _, v = s.partition(":")
        k, v = k.strip(), v.strip()
        if v == "":
            path.append((ind, k))
        elif keys == ["env", "variables"]:
            spec["env"]["variables"][k] = unq(v)
        elif keys == ["artifacts"]:
            spec["artifacts"][k] = unq(v)
        elif not keys:
            spec[k] = unq(v)
        i += 1
    return spec

try:
    import yaml
    spec = yaml.safe_load(text); parser = "PyYAML"
except ImportError:
    spec = minimal_parse(text); parser = "built-in minimal parser"

out = ["set -o pipefail",
       "echo '[runner] parsed buildspec with %s'" % parser]
for k, v in ((spec.get("env") or {}).get("variables") or {}).items():
    # CodeBuild precedence: start-build override > project variable > buildspec default.
    # A variable already set in the environment plays the role of the project variable.
    out.append('if [ -z "${%s+x}" ]; then export %s=%s; fi' % (k, k, shlex.quote(str(v))))
    out.append('echo "[runner] env %s=${%s}"' % (k, k))
phases = spec.get("phases") or {}
for ph in PHASES:
    cmds = (phases.get(ph) or {}).get("commands") or []
    out.append("echo; echo '[runner] ===== PHASE %s (%d commands) ====='" % (ph.upper(), len(cmds)))
    for n, c in enumerate(cmds, 1):
        label = c.splitlines()[0][:70].replace("'", "")
        out.append("echo '[runner] %s #%d: %s'" % (ph, n, label))
        out.append(c)
        out.append("rc=$?; if [ $rc -ne 0 ]; then echo; "
                   "echo '[runner] PHASE %s FAILED (command #%d exit '$rc')'; exit $rc; fi" % (ph.upper(), n))
    out.append("echo '[runner] PHASE %s SUCCEEDED'" % ph.upper())
art = spec.get("artifacts") or {}
out.append("echo; echo '[runner] artifacts base-directory: %s (not uploaded locally)'"
           % str(art.get("base-directory", ".")).replace("'", ""))
print("\n".join(out))
PY

echo "[runner] app dir: $APP_DIR"
( cd "$APP_DIR" && bash "$GEN" )
RC=$?
echo
if [ $RC -eq 0 ]; then echo "[runner] BUILD SUCCEEDED (local)"; else echo "[runner] BUILD FAILED (local, exit $RC)"; fi
exit $RC
