"""Answer a command's prompts, from a terminal it believes in.

    python3 test/ask.py 'first|second|…' -- cmd arg…

braid asks two things before it opens anything — which agents this repository uses, and
what each seat costs — and both are guarded by `-t 0`. Redirecting stdin does not
exercise them; it exercises the branch that skips them. So the command is run under a
pty and answered when it stops to ask.

Not a way to test an agent: e2e never launches one, and this does not either. It tests
the questions braid asks in its own voice, which are ordinary code and were otherwise
reachable only by hand.

Output goes to stdout, escape sequences and all — the caller greps it. Exits 1 if the
command outlives the timeout, so a prompt that stops being answered fails the suite
rather than hanging it.
"""

import os
import pty
import select
import sys
import time

TIMEOUT = 90.0
# Long enough that a prompt is finished being written, short enough to stay out of the
# way. The alternative is matching prompt text, which would put a copy of every question
# braid asks in a second file, to drift.
SETTLED = 0.35


def main() -> int:
    answers = [a for a in sys.argv[1].split("|")]
    command = sys.argv[sys.argv.index("--") + 1:]

    pid, fd = pty.fork()
    if pid == 0:
        os.environ["TERM"] = "dumb"
        os.execvp(command[0], command)

    out = b""
    sent = 0
    quiet_since = time.time()
    deadline = time.time() + TIMEOUT
    timed_out = True

    while time.time() < deadline:
        readable, _, _ = select.select([fd], [], [], 0.2)
        if readable:
            try:
                chunk = os.read(fd, 65536)
            except OSError:  # the child closed its end
                timed_out = False
                break
            if not chunk:
                timed_out = False
                break
            out += chunk
            quiet_since = time.time()
            continue
        if sent >= len(answers) or time.time() - quiet_since < SETTLED:
            continue
        # A prompt, rather than a line of progress: braid's questions all end in the
        # cursor position where the answer goes.
        if out.decode("utf-8", "replace").rstrip("\n").rstrip().endswith((":", "]")):
            os.write(fd, (answers[sent] + "\n").encode())
            sent += 1
            quiet_since = time.time()

    try:
        os.kill(pid, 9)
    except OSError:
        pass
    os.waitpid(pid, 0)
    sys.stdout.write(out.decode("utf-8", "replace"))
    if timed_out:
        sys.stderr.write(f"ask.py: timed out after {TIMEOUT}s, {sent}/{len(answers)} answered\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
