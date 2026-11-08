"""Ship a finished step: commit, push, pull request, wait for CI, squash merge (ADR 0013).

The owner authorised this automation: a milestone step (or a fix) is merged into main without waiting for a manual
review, but ONLY when the local checks and the required CI checks are green. On any failure the script stops and
leaves the pull request open, with the reason printed.

Usage, from the repository root, on the step branch (never on main):
  python -I -X utf8 tools/ship_step.py --title "M1: transport and codec" --body-file pr.md [--commit "message"]
  --commit "message"   commit every pending change first (git add -A) with this message
  --no-merge           stop after the pull request is open and CI is green
  --dry-run            print what would happen, change nothing

Steps:
  1. refuses to run on main or with a dirty tree (unless --commit);
  2. runs the local checks: tools/check_docs.py and, when it exists, Tests/run_tests.py;
  3. merges origin/main into the branch if main moved (a conflict stops the script);
  4. pushes the branch and opens the pull request (or reuses the open one);
  5. waits for the CI checks of the pull request (gh pr checks --watch);
  6. squash merges with --delete-branch, then updates the local main.
The wiki is published by the "Wiki sync" workflow after the merge, not by this script.
"""
import argparse
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CO_AUTHOR = "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"


def run(cmd, check=True, capture=True, dry=False):
    print("$ " + " ".join(cmd))
    if dry:
        return subprocess.CompletedProcess(cmd, 0, "", "")
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=capture, text=True)
    if check and proc.returncode != 0:
        sys.exit(f"Stopped: {' '.join(cmd)} failed\n{proc.stderr or proc.stdout}")
    return proc


def out(cmd):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True).stdout.strip()


def local_checks(dry):
    run([sys.executable, "-I", "-X", "utf8", "tools/check_docs.py"], capture=False, dry=dry)
    tests = os.path.join(ROOT, "Tests", "run_tests.py")
    if os.path.isfile(tests):
        run([sys.executable, "-I", "-X", "utf8", tests], capture=False, dry=dry)


def open_pr(branch, title, body_file, dry):
    existing = out(["gh", "pr", "view", branch, "--json", "number,state", "--jq", "select(.state==\"OPEN\") | .number"])
    if existing:
        print(f"Reusing the open pull request #{existing}.")
        return existing
    if dry:
        print("(dry run) would open a pull request")
        return "0"
    run(["gh", "pr", "create", "--base", "main", "--head", branch, "--title", title, "--body-file", body_file])
    return out(["gh", "pr", "view", branch, "--json", "number", "--jq", ".number"])


def wait_for_checks(number):
    # checks need a few seconds to be registered after the push
    for _ in range(12):
        if out(["gh", "pr", "checks", number, "--json", "name", "--jq", "length"]) not in ("", "0"):
            break
        time.sleep(10)
    proc = subprocess.run(["gh", "pr", "checks", number, "--watch", "--fail-fast", "--interval", "15"], cwd=ROOT)
    if proc.returncode != 0:
        sys.exit(f"Stopped: the CI checks of pull request #{number} are not green. The pull request stays open.")


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--title", required=True)
    ap.add_argument("--body-file", required=True)
    ap.add_argument("--commit")
    ap.add_argument("--no-merge", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    dry = a.dry_run

    branch = out(["git", "branch", "--show-current"])
    if branch in ("", "main"):
        sys.exit("Stopped: run this on a step branch (step/m1-..., fix/..., docs/...), never on main.")
    if not os.path.isfile(os.path.join(ROOT, a.body_file)) and not os.path.isfile(a.body_file):
        sys.exit(f"Stopped: {a.body_file} not found.")

    if out(["git", "status", "--porcelain"]):
        if not a.commit:
            sys.exit("Stopped: there are uncommitted changes. Commit them or pass --commit \"message\".")
        local_checks(dry)
        run(["git", "add", "-A"], dry=dry)
        run(["git", "commit", "-m", a.commit + "\n\n" + CO_AUTHOR], dry=dry)
    else:
        local_checks(dry)

    run(["git", "fetch", "origin", "main"], dry=dry)
    if out(["git", "rev-list", "--count", "HEAD..origin/main"]) not in ("", "0"):
        merge = run(["git", "merge", "--no-edit", "origin/main"], check=False, dry=dry)
        if merge.returncode != 0:
            run(["git", "merge", "--abort"], check=False, dry=dry)
            sys.exit("Stopped: merging origin/main gives conflicts. Resolve them by hand, run the checks, ship again.")
        local_checks(dry)

    run(["git", "push", "-u", "origin", branch], dry=dry)
    number = open_pr(branch, a.title, a.body_file, dry)
    if dry:
        print("(dry run) would wait for CI and squash merge")
        return 0
    wait_for_checks(number)
    if a.no_merge:
        print(f"CI is green. Pull request #{number} left open (--no-merge).")
        return 0
    run(["gh", "pr", "merge", number, "--squash", "--delete-branch"])
    run(["git", "switch", "main"], check=False)
    run(["git", "pull", "--ff-only", "origin", "main"], check=False)
    print(f"Merged pull request #{number}. The wiki is published by the 'Wiki sync' workflow.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
