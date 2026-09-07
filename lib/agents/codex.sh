#!/usr/bin/env bash
# Adapter — OpenAI Codex CLI.
#
# Codex has hooks — ~/.codex/hooks.json, and the schema is the same shape as Claude
# Code's. braid does not install into it yet, and the reason is not effort:
#
#   - it is registered per machine, not per repository. Claude's live in a committed
#     .claude/settings.json, which is what makes "this repository is set up for braid" a
#     reviewable fact. A global hook is a fact about a laptop.
#   - hooks are gated by a trust model, with hashes recorded in config.toml. What braid
#     would have to do to register one honestly has not been verified here, and
#     --dangerously-bypass-hook-trust is not something a tool should pass on your behalf.
#
# So for now two things arrive by other means, and braid handles both:
#
#   the contract   goes into the prompt instead of arriving at session start
#   status         written by .braid/finish.sh on exit, not by a stop hook
#
# What does not carry over is the PreToolUse guard: nothing can deny a `git push`
# mid-session. The per-worktree pre-push hook replaces it — narrower, but it is the
# part that actually costs something to clean up.
#
# No seat models are declared. Model names change faster than this file can, and an
# adapter that guesses one is worse than an adapter that lets the CLI choose. Set them
# per repository:
#
#   BRAID_MODEL_ORCHESTRATE=…    BRAID_MODEL_WORK=…
#
# Flags move between versions — `--full-auto` was the right answer and is gone from
# 0.151. `braid doctor` probes whichever flags are set here against the installed CLI's
# own help, so a rename is reported before a wave rather than discovered as eight
# workers that died at launch. When yours disagrees:
#
#   BRAID_AGENT_ARGS="-s danger-full-access"
#
# or drop to the generic adapter and give it the whole command line.

: "${BRAID_AGENT_ARGS:=--sandbox workspace-write}"

# What a seat with a terminal does about approvals. `codex exec` never asks anybody
# anything, so the flag exists only on the interactive CLI — and without it a worker
# in a pane stops on the first approval prompt with nobody sitting in front of it.
# Set it to `on-request` for a seat you intend to babysit.
: "${BRAID_APPROVAL_POLICY:=never}"

agent_available() { command -v codex >/dev/null 2>&1; }

agent_version() { codex --version 2>/dev/null | head -1; }

agent_seat_model() { :; }

# Left to the repository. `braid setup` asks which model each complexity level means
# here, because that is the moment somebody with the CLI installed can answer it.
#
#   BRAID_MODEL_LOW=…  BRAID_MODEL_STANDARD=…  BRAID_MODEL_HIGH=…
agent_complexity_model() { :; }

# Anything the CLI accepts. Validating against a list braid cannot keep current would
# reject working configurations.
agent_models() { :; }

agent_injects_contract() { return 1; }

# Codex keeps skills in ~/.codex/skills, which links into the shared ~/.agents/skills the
# agents use between them, and the installer puts braid's there. It invokes them with `$`
# rather than `/` — which is the whole reason the prefix belongs to the adapter and not to
# the caller.
agent_loads_skills() { return 0; }
agent_skill_prefix() { printf '$'; }

# workspace-write rather than --dangerously-bypass-approvals-and-sandbox. A worker is
# already confined to its own worktree, and its dependencies were installed by
# braid_provision before it started, so the sandbox costs it nothing it needs — and a
# default whose own name says "dangerously" is not a default.
agent_auto_mode() { printf '%s --ask-for-approval %s' "$BRAID_AGENT_ARGS" "$BRAID_APPROVAL_POLICY"; }
# Both spellings, because braid launches both: the TUI for a seat with a terminal and
# `codex exec` for a detached one, and they do not accept the same flags —
# --ask-for-approval is rejected outright by exec, which has nobody to ask.
agent_auto_mode_probe() {
    local flag
    for flag in $BRAID_AGENT_ARGS; do
        [[ "$flag" == -* ]] || continue
        codex --help 2>/dev/null | grep -q -- "$flag" || return 1
        codex exec --help 2>/dev/null | grep -q -- "$flag" || return 1
    done
    codex --help 2>/dev/null | grep -q -- '--ask-for-approval'
}

# The interactive CLI, not `codex exec`. This is the seat somebody is sitting in front
# of — `braid setup` asking what the verify command is, `braid design` grilling a spec,
# an orchestrator judging a branch — and `codex exec` is documented as "run Codex
# non-interactively": it reads the prompt, works until it decides it is finished, and
# has no way to ask a question. `braid setup` under it looked like an agent doing
# things to the repository and never getting to the conversation, because that is
# exactly what it was.
agent_command() {
    # shellcheck disable=SC2034  # the adapter signature is fixed; this agent needs no worktree
    local worktree="$1" model="$2" prompt="$3"
    # shellcheck disable=SC2086  # BRAID_AGENT_ARGS is a flag list on purpose
    if [[ -n "$model" ]]; then
        printf 'codex %s --ask-for-approval %q --model %q %q' \
            "$BRAID_AGENT_ARGS" "$BRAID_APPROVAL_POLICY" "$model" "$prompt"
    else
        printf 'codex %s --ask-for-approval %q %q' \
            "$BRAID_AGENT_ARGS" "$BRAID_APPROVAL_POLICY" "$prompt"
    fi
}

# For a launcher with no terminal. `exec` is the right tool here and the wrong one
# above: it is the half of this CLI that runs without anybody watching.
agent_command_headless() {
    # shellcheck disable=SC2034  # the adapter signature is fixed; this agent needs no worktree
    local worktree="$1" model="$2" prompt="$3"
    # shellcheck disable=SC2086  # BRAID_AGENT_ARGS is a flag list on purpose
    if [[ -n "$model" ]]; then
        printf 'codex exec %s --model %q %q' "$BRAID_AGENT_ARGS" "$model" "$prompt"
    else
        printf 'codex exec %s %q' "$BRAID_AGENT_ARGS" "$prompt"
    fi
}

agent_transcript_dir() { printf '%s/.codex/sessions' "$HOME"; }
