#!/usr/bin/env python3

import os
import sys
import time
import shutil
import subprocess
from pathlib import Path
from datetime import datetime


# ============================================================
# ARIZONA FORESTATION DAO
# COMPLETE CODESPACES LOCAL AUDIT + REMEDIATION RUNNER
#
# PURPOSE:
#   Run OpenCode against the CURRENT repository and perform
#   a complete local/offline Solidity security audit,
#   remediation cycle, regression testing, and final report.
#
# SAFETY:
#   NO RPC
#   NO LIVE BLOCKCHAIN
#   NO DEPLOYMENT
#   NO BROADCAST
#   NO TRANSACTIONS
#   NO FORK
#   NO GAS
#   NO GITHUB PUSH
#   NO PRIVATE KEYS
#   NO SEED PHRASES
#
# OUTPUT:
#   AUDIT_PROGRESS.md
#   FINAL_AUDIT_REPORT.md
#
# LIVE:
#   OpenCode output is streamed directly to the Codespace
#   terminal.
#
#   If OpenCode is quiet for 30 seconds, a heartbeat appears.
#
# RESUME:
#   OpenCode is instructed to inspect AUDIT_PROGRESS.md and
#   continue from the current repository state.
# ============================================================


# ============================================================
# CONFIGURATION
# ============================================================

REPO = Path("/workspaces/arizona-forestation-dao").resolve()

PROGRESS_FILE = REPO / "AUDIT_PROGRESS.md"
FINAL_REPORT = REPO / "FINAL_AUDIT_REPORT.md"

MODEL = os.environ.get(
    "OPENCODE_MODEL",
    "opencode/nemotron-3-ultra-free"
)

HEARTBEAT_SECONDS = 30

MAX_OPENCODE_RETRIES = 8

RETRY_DELAY_SECONDS = 15

BUILD_TIMEOUT = 1200

TEST_TIMEOUT = 1800


# ============================================================
# DISPLAY
# ============================================================

def timestamp():
    return datetime.now().strftime(
        "%Y-%m-%d %H:%M:%S"
    )


def banner(title):
    print()
    print("=" * 80, flush=True)
    print(title, flush=True)
    print("=" * 80, flush=True)


def log(message):
    print(
        f"[{timestamp()}] {message}",
        flush=True
    )


# ============================================================
# HARD SAFETY ENVIRONMENT
# ============================================================

BLOCKED_RPC_VARIABLES = [
    "RPC_URL",
    "ARBITRUM_RPC_URL",
    "ETH_RPC_URL",
    "MAINNET_RPC_URL",
    "SEPOLIA_RPC_URL",
    "GOERLI_RPC_URL",
    "ALCHEMY_API_KEY",
    "INFURA_API_KEY",
    "QUICKNODE_API_KEY",
    "ANKR_API_KEY",
    "ETHERSCAN_API_KEY",
    "ARBISCAN_API_KEY",
]


for variable in BLOCKED_RPC_VARIABLES:
    os.environ.pop(variable, None)


os.environ["NO_RPC"] = "1"
os.environ["NO_DEPLOY"] = "1"
os.environ["NO_BROADCAST"] = "1"
os.environ["GAS_ZERO"] = "1"
os.environ["FOUNDRY_OFFLINE"] = "1"


# ============================================================
# REPOSITORY
# ============================================================

if not REPO.exists():
    print(
        f"ERROR: Repository does not exist:\n{REPO}",
        flush=True
    )
    sys.exit(1)


os.chdir(REPO)


# ============================================================
# TOOL DISCOVERY
# ============================================================

def executable(name):
    return shutil.which(name)


OPENCODE = executable("opencode")
FORGE = executable("forge")
GIT = executable("git")


# ============================================================
# COMMAND EXECUTION
# ============================================================

def run_command(command, timeout=600):
    """
    Run a local command and stream its complete output after
    completion.

    This is intentionally used for short verification commands.
    OpenCode itself uses the dedicated live streaming function.
    """

    print(
        "\n$ " + " ".join(command),
        flush=True
    )

    try:
        result = subprocess.run(
            command,
            cwd=str(REPO),
            env=os.environ.copy(),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout
        )

        if result.stdout:
            print(
                result.stdout,
                end="",
                flush=True
            )

        print(
            f"\n[EXIT CODE: {result.returncode}]",
            flush=True
        )

        return result.returncode

    except subprocess.TimeoutExpired:
        print(
            f"\n❌ COMMAND TIMEOUT: {timeout} seconds",
            flush=True
        )

        return 124

    except Exception as exc:
        print(
            f"\n❌ COMMAND ERROR: {exc}",
            flush=True
        )

        return 1


# ============================================================
# LIVE OPENCODE STREAM
# ============================================================

def run_opencode_live(prompt):
    """
    Launch OpenCode and continuously stream its stdout/stderr
    to the Codespace terminal.

    Heartbeat messages appear if OpenCode produces no output
    for HEARTBEAT_SECONDS.
    """

    command = [
        OPENCODE,
        "run",
        "--auto",
        "--print-logs",
        "--log-level",
        "INFO",
        "--model",
        MODEL,
        "--dir",
        str(REPO),
        prompt
    ]

    banner("📡 LIVE OPENCODE STREAM")

    print(
        "OpenCode output will appear LIVE below.",
        flush=True
    )

    print(
        f"Heartbeat interval: {HEARTBEAT_SECONDS}s",
        flush=True
    )

    print(
        f"Model: {MODEL}",
        flush=True
    )

    print(
        "RPC: DISABLED",
        flush=True
    )

    print(
        "Deployment: DISABLED",
        flush=True
    )

    print(
        "Broadcast: DISABLED",
        flush=True
    )

    print(
        "Gas: ZERO",
        flush=True
    )

    print(
        "Git push: DISABLED",
        flush=True
    )

    print(
        "\n------------------------------------------------------------",
        flush=True
    )

    started = time.time()

    last_output = started

    line_count = 0

    process = None

    try:

        process = subprocess.Popen(
            command,
            cwd=str(REPO),
            env=os.environ.copy(),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            universal_newlines=True
        )

        while True:

            line = process.stdout.readline()

            if line:

                print(
                    line,
                    end="",
                    flush=True
                )

                last_output = time.time()

                line_count += 1

                continue

            if process.poll() is not None:
                break

            now = time.time()

            quiet_seconds = now - last_output

            if quiet_seconds >= HEARTBEAT_SECONDS:

                elapsed = int(
                    now - started
                )

                print(
                    "\n"
                    f"💓 HEARTBEAT | OpenCode still running | "
                    f"elapsed={elapsed}s | "
                    f"quiet={int(quiet_seconds)}s | "
                    f"lines={line_count}",
                    flush=True
                )

                last_output = now

            time.sleep(0.1)

        process.stdout.close()

        return_code = process.wait()

        elapsed = int(
            time.time() - started
        )

        print(
            "\n------------------------------------------------------------",
            flush=True
        )

        print(
            "📊 OPENCODE RUN FINISHED",
            flush=True
        )

        print(
            f"Exit code : {return_code}",
            flush=True
        )

        print(
            f"Elapsed   : {elapsed}s",
            flush=True
        )

        print(
            f"Lines     : {line_count}",
            flush=True
        )

        return return_code

    except KeyboardInterrupt:

        print(
            "\n\n🛑 CTRL-C RECEIVED",
            flush=True
        )

        if process is not None:

            try:
                process.terminate()
            except Exception:
                pass

        print(
            "Repository state has been preserved.",
            flush=True
        )

        print(
            "You can rerun this script to continue.",
            flush=True
        )

        raise

    except Exception as exc:

        print(
            f"\n❌ OPENCODE STREAM ERROR: {exc}",
            flush=True
        )

        return 1


# ============================================================
# AUDIT PROMPT
# ============================================================

AUDIT_PROMPT = r"""
You are the senior Solidity security engineer responsible
for completing the LOCAL FINAL SECURITY AUDIT AND REMEDIATION
of the Arizona Forestation DAO.

============================================================
ABSOLUTE SAFETY
============================================================

Work ONLY in the current local repository.

NEVER:

- connect to RPC;
- connect to a live blockchain;
- deploy;
- broadcast;
- send transactions;
- fork a live chain;
- spend gas;
- request private keys;
- request seed phrases;
- modify wallet credentials;
- modify SSH credentials;
- push to GitHub.

All Foundry commands must be local/offline.

Use:

forge build --offline

forge test --offline -vvv

Do not remove --offline.

============================================================
CURRENT REPOSITORY
============================================================

Work from the actual current repository state.

Do NOT assume the repository is new.

Before modifying anything inspect:

- git status;
- recent commits;
- AUDIT_PROGRESS.md;
- FINAL_AUDIT_REPORT.md if present;
- every Solidity contract;
- interfaces;
- libraries;
- tests;
- scripts;
- Foundry configuration;
- OpenZeppelin dependencies;
- documentation;
- previous remediation.

Do not blindly redo completed remediation.

Do not undo valid security fixes.

Continue from the first genuinely incomplete issue.

============================================================
OBS TOKEN
============================================================

Required OBS token:

0x2D8760e2877148d239a54952A458710553B2B54b

Verify the actual implementation.

Check:

- exact token address binding;
- immutable binding where appropriate;
- ERC20 compatibility;
- decimals;
- transfer;
- receipt;
- vault receipt;
- balance accounting;
- allowance behavior;
- SafeERC20 behavior;
- zero-address handling;
- token substitution protection;
- failed transfer handling.

Do not merely check whether a function name exists.

============================================================
AUTHORIZED ADMIN
============================================================

Authorized administrative wallet:

0xaF570ce3b32D765b1236635B0f541a7487A1fB8e

Verify actual authorization boundaries.

Check:

- initialization;
- access control;
- privilege escalation;
- unauthorized configuration;
- unauthorized withdrawal;
- permanent revocation;
- irreversible locking.

============================================================
BONDING CURVE
============================================================

Required unlock threshold:

5,000,000,000 DAI.

Audit the actual mathematics.

Verify:

- DAI decimals;
- OBS decimals;
- price calculation;
- purchase calculation;
- accumulated DAI;
- threshold accounting;
- exact threshold;
- below threshold;
- above threshold;
- rounding;
- precision;
- overflow;
- underflow;
- repeated purchases;
- repeated exits;
- threshold bypass;
- accounting invariants.

Add boundary tests.

Do not merely trust comments.

============================================================
LP GOVERNANCE
============================================================

Required behavior:

- 100 LP tokens issued monthly;
- unused LP expires at the appropriate monthly boundary;
- 50 LP required for a proposal;
- 1 LP = 1 vote;
- weighted voting;
- proposal execution;
- quorum;
- double-vote protection;
- voting deadline.

Audit:

- month boundaries;
- expiry;
- snapshot behavior;
- proposal creation;
- voting;
- duplicate votes;
- quorum;
- majority;
- execution;
- expired LP rejection.

CRITICAL:

Voting power must not unexpectedly disappear from an active
proposal because the calendar month changes.

Test this explicitly.

============================================================
VAULT
============================================================

The DAO must safely receive and hold OBS.

OBS in the vault must NOT become spendable merely because
tokens exist in the vault.

Release must remain subject to actual enforceable:

- bonding conditions;
- governance;
- proposals;
- quorum;
- authorization;
- milestones;
- spending controls;
- project state;
- timeout requirements.

Audit:

- arbitrary withdrawal;
- admin drain;
- arbitrary recipient;
- token substitution;
- accounting mismatch;
- reentrancy;
- approval abuse;
- unauthorized release.

============================================================
ROBOT AUTHORIZATION
============================================================

Audit future Roomie humanoid robot / MCU integration.

Verify:

- robot authorization;
- public-key configuration;
- key rotation;
- nonce handling;
- replay protection;
- domain separation;
- signature binding;
- project binding;
- milestone binding;
- expiration;
- final revocation;
- permanent lock.

The authorized wallet must be able to configure the future
robot/MCU public-key information after the hardware is
actually received.

Key rotation must be possible before permanent lockdown.

The authorized wallet must be able to permanently revoke
its update authority.

After final revocation, protected configuration must become
permanently immutable according to the contract design.

============================================================
PQC
============================================================

Hybrid post-quantum security must be audited honestly.

NEVER use:

return true

to simulate cryptographic verification.

NEVER pretend ordinary ECDSA/ECDSA-style verification is PQC.

NEVER create fake PQC verification.

If genuine PQC verification requires an external verifier,
precompile, library, or hardware component that cannot be
executed locally:

- document the dependency;
- fail closed;
- do not claim PQC is locally verified.

Distinguish:

A. cryptography actually enforced by Solidity;

B. cryptography requiring an external verifier;

C. hardware/MCU verification;

D. physical-world actions.

============================================================
BIOMETRIC PRIVACY
============================================================

Biometric templates must NEVER be stored in:

- Solidity storage;
- contract events;
- source code;
- tests;
- scripts;
- repository files;
- documentation containing actual biometric templates.

Only appropriate public cryptographic verification material
may be represented on-chain.

Biometric templates must remain exclusively on the proper
hardware/MCU layer.

The Solidity contract cannot prove that a physical human
biometric was correctly measured unless an external trusted
verification system provides cryptographically verifiable
evidence.

Document this limitation.

============================================================
IMMUTABILITY
============================================================

Audit:

- configuration;
- public keys;
- key rotation;
- administrator authority;
- permanent revocation;
- final lock;
- irreversible operations.

Verify that final lockdown cannot be reversed.

============================================================
PROJECT LIFECYCLE
============================================================

Audit the entire lifecycle:

- project creation;
- proposal;
- voting;
- approval;
- robot authorization;
- milestone authorization;
- spending;
- timeout;
- completion;
- failure;
- expiration;
- reauthorization.

Verify approximately two-month authorization behavior.

Distinguish blockchain-enforceable conditions from:

- physical-world events;
- human behavior;
- robot behavior;
- MCU behavior;
- external services;
- off-chain processes.

============================================================
FORESTATION PROJECT CATEGORIES
============================================================

Review how the implementation represents or controls:

- Arizona forestation;
- Arizona garden projects;
- off-grid solar;
- water generation for plants;
- battery storage;
- environmentally responsible biotechnology;
- bamboo cultivation;
- sustainable bamboo harvesting;
- distribution of bamboo building material.

Do not claim the blockchain can prove physical-world outcomes
unless a trusted oracle/hardware verification mechanism
actually exists.

============================================================
GENERAL SECURITY
============================================================

Perform a complete Solidity security review covering:

- access control;
- privilege escalation;
- initialization;
- ownership;
- reentrancy;
- SafeERC20;
- ERC20 assumptions;
- signature replay;
- nonce handling;
- domain separation;
- signature malleability;
- timestamp assumptions;
- month boundaries;
- decimals;
- arithmetic;
- overflow;
- underflow;
- denial of service;
- unbounded loops;
- storage corruption;
- proposal execution;
- voting accounting;
- vault accounting;
- emergency paths;
- irreversible operations;
- griefing;
- front-running where relevant;
- state-machine violations.

============================================================
AUDIT CHECKPOINT
============================================================

Maintain:

AUDIT_PROGRESS.md

Record:

- current phase;
- completed phases;
- current task;
- files inspected;
- files modified;
- vulnerabilities;
- severity;
- remediation;
- tests;
- failures;
- unresolved issues;
- next action.

Update the checkpoint after meaningful milestones.

============================================================
12 AUDIT PHASES
============================================================

PHASE 1:
Repository discovery.

PHASE 2:
Requirement matrix.

PHASE 3:
OBS token integration.

PHASE 4:
Bonding curve and 5B DAI threshold.

PHASE 5:
LP and governance.

PHASE 6:
PQC and robot authorization.

PHASE 7:
Biometric and MCU security.

PHASE 8:
Vault security.

PHASE 9:
Project lifecycle.

PHASE 10:
General Solidity security.

PHASE 11:
Remediation and regression testing.

PHASE 12:
Final audit and final report.

============================================================
LIVE PROGRESS
============================================================

Before every phase print:

▶ PHASE N/12: NAME

During work print:

🔎 Inspecting FILE

🛠️ Modifying FILE

🧪 Running COMMAND

❌ Failure detected

🔧 Applying remediation

🔁 Retesting

✅ Regression test passed

Do not silently remain stuck.

If blocked:

1. document the blocker;
2. classify it;
3. continue with another independent task;
4. return later.

Do NOT repeatedly execute an unchanged failing command.

============================================================
REMEDIATION
============================================================

Fix every technically valid vulnerability.

After meaningful code changes run:

forge build --offline

then:

forge test --offline -vvv

Inspect actual failures.

Fix root causes.

Add regression tests.

Rerun build.

Rerun tests.

Never weaken security simply to make tests pass.

Never create fake tests.

Never remove a security requirement merely because it is
difficult to implement.

If a requirement is impossible for Solidity alone to guarantee,
document it honestly.

============================================================
FINAL REPORT
============================================================

Create:

FINAL_AUDIT_REPORT.md

The report MUST contain:

1. Executive summary
2. Architecture
3. Contracts reviewed
4. Tests reviewed
5. OBS token integration
6. Bonding curve
7. 5B DAI threshold
8. LP issuance
9. LP expiration
10. Voting
11. Snapshot behavior
12. Quorum
13. Proposal execution
14. Vault security
15. Robot authorization
16. PQC security
17. Biometric handling
18. MCU dependency
19. Project lifecycle
20. Milestones
21. Spending controls
22. Timeouts
23. Immutability
24. Key rotation
25. Final revocation
26. Deployment configuration
27. Findings
28. Severity
29. Remediation
30. Regression tests
31. Exact forge build result
32. Exact forge test result
33. External dependencies
34. Known limitations
35. Remaining risks
36. Production-readiness assessment

Clearly separate:

A. ENFORCED AND LOCALLY TESTED

B. IMPLEMENTED BUT DEPENDENT ON EXTERNAL INFRASTRUCTURE

C. IMPOSSIBLE FOR SOLIDITY ALONE TO GUARANTEE

D. REMAINING RISKS

Passing tests does NOT automatically mean production-ready.

============================================================
FINAL COMPLETION CONDITION
============================================================

Do not claim the audit is complete until ALL are true:

- all 12 phases are genuinely complete;
- remediation is complete;
- unresolved issues are documented;
- forge build --offline passes;
- forge test --offline -vvv passes;
- FINAL_AUDIT_REPORT.md exists;
- AUDIT_PROGRESS.md exists;
- AUDIT_PROGRESS.md explicitly says:

STATUS: COMPLETE

If any condition is false, do NOT certify the DAO.

============================================================
FINAL RULE
============================================================

Do not deploy.

Do not broadcast.

Do not connect to a blockchain.

Do not use RPC.

Do not spend gas.

Do not push GitHub.

Work locally until the audit is actually complete.
"""


# ============================================================
# STARTUP
# ============================================================

banner(
    "🌳 ARIZONA FORESTATION DAO"
)

print(
    "CODESPACES LOCAL SECURITY AUDIT + REMEDIATION",
    flush=True
)

print(
    f"\nRepository : {REPO}",
    flush=True
)

print(
    f"Model      : {MODEL}",
    flush=True
)

print(
    "RPC        : DISABLED",
    flush=True
)

print(
    "Deployment : DISABLED",
    flush=True
)

print(
    "Broadcast  : DISABLED",
    flush=True
)

print(
    "Transactions: DISABLED",
    flush=True
)

print(
    "Gas        : ZERO",
    flush=True
)

print(
    "Git push   : DISABLED",
    flush=True
)

print(
    "Mode       : LOCAL / OFFLINE",
    flush=True
)


# ============================================================
# TOOLCHAIN CHECK
# ============================================================

banner("🔎 TOOLCHAIN CHECK")


if OPENCODE is None:

    print(
        "❌ OpenCode was not found in PATH.",
        flush=True
    )

    print(
        "Install/configure OpenCode before running this script.",
        flush=True
    )

    sys.exit(1)


if FORGE is None:

    print(
        "❌ forge was not found in PATH.",
        flush=True
    )

    print(
        "Install/configure Foundry before running this script.",
        flush=True
    )

    sys.exit(1)


print(
    f"OpenCode: {OPENCODE}",
    flush=True
)

print(
    f"Forge   : {FORGE}",
    flush=True
)


run_command(
    [OPENCODE, "--version"],
    timeout=30
)

run_command(
    [FORGE, "--version"],
    timeout=30
)


# ============================================================
# GIT STATE
# ============================================================

banner("🌿 CURRENT GIT STATE")


if GIT:

    run_command(
        [GIT, "status", "--short"],
        timeout=30
    )

    run_command(
        [GIT, "branch", "--show-current"],
        timeout=30
    )

    run_command(
        [GIT, "log", "-5", "--oneline"],
        timeout=30
    )

else:

    print(
        "⚠️ git not found.",
        flush=True
    )


# ============================================================
# EXISTING CHECKPOINT
# ============================================================

banner("📌 AUDIT CHECKPOINT")


if PROGRESS_FILE.exists():

    print(
        "✅ AUDIT_PROGRESS.md FOUND",
        flush=True
    )

    try:

        lines = PROGRESS_FILE.read_text(
            encoding="utf-8",
            errors="replace"
        ).splitlines()

        print(
            "\n----- LAST 100 LINES -----",
            flush=True
        )

        print(
            "\n".join(lines[-100:]),
            flush=True
        )

        print(
            "----- END CHECKPOINT -----",
            flush=True
        )

    except Exception as exc:

        print(
            f"⚠️ Unable to read checkpoint: {exc}",
            flush=True
        )

else:

    print(
        "📌 No AUDIT_PROGRESS.md found.",
        flush=True
    )

    print(
        "OpenCode will create/maintain it.",
        flush=True
    )


# ============================================================
# EXISTING REPORT
# ============================================================

banner("📄 EXISTING FINAL REPORT")


if FINAL_REPORT.exists():

    print(
        "✅ FINAL_AUDIT_REPORT.md already exists.",
        flush=True
    )

    try:

        size = FINAL_REPORT.stat().st_size

        lines = len(
            FINAL_REPORT.read_text(
                encoding="utf-8",
                errors="replace"
            ).splitlines()
        )

        print(
            f"Lines: {lines}",
            flush=True
        )

        print(
            f"Bytes: {size}",
            flush=True
        )

    except Exception as exc:

        print(
            f"⚠️ Unable to inspect report: {exc}",
            flush=True
        )

else:

    print(
        "📌 No final report exists yet.",
        flush=True
    )


# ============================================================
# INITIAL OFFLINE BUILD
# ============================================================

banner("🔨 INITIAL OFFLINE BUILD")


initial_build = run_command(
    [
        FORGE,
        "build",
        "--offline"
    ],
    timeout=BUILD_TIMEOUT
)


if initial_build == 0:

    print(
        "✅ Initial offline build passed.",
        flush=True
    )

else:

    print(
        "⚠️ Initial build failed.",
        flush=True
    )

    print(
        "OpenCode will inspect the actual failure.",
        flush=True
    )


# ============================================================
# OPENCODE RETRY LOOP
# ============================================================

banner("🚀 STARTING AUDIT / REMEDIATION")


opencode_success = False

last_opencode_rc = 1


for attempt in range(
    1,
    MAX_OPENCODE_RETRIES + 1
):

    banner(
        f"OPENCODE ATTEMPT {attempt}/"
        f"{MAX_OPENCODE_RETRIES}"
    )

    if attempt > 1:

        print(
            f"Waiting {RETRY_DELAY_SECONDS}s before retry...",
            flush=True
        )

        time.sleep(
            RETRY_DELAY_SECONDS
        )

    last_opencode_rc = run_opencode_live(
        AUDIT_PROMPT
    )

    if last_opencode_rc == 0:

        opencode_success = True

        print(
            "\n✅ OpenCode process completed.",
            flush=True
        )

        break

    print(
        f"\n⚠️ OpenCode exited with code "
        f"{last_opencode_rc}.",
        flush=True
    )

    print(
        "Repository changes remain preserved.",
        flush=True
    )

    print(
        "The next attempt will inspect the current state.",
        flush=True
    )


# ============================================================
# FINAL BUILD
# ============================================================

banner("🧪 FINAL OFFLINE BUILD")


final_build_rc = run_command(
    [
        FORGE,
        "build",
        "--offline"
    ],
    timeout=BUILD_TIMEOUT
)


# ============================================================
# FINAL TESTS
# ============================================================

banner("🧪 FINAL OFFLINE TEST SUITE")


if final_build_rc == 0:

    final_test_rc = run_command(
        [
            FORGE,
            "test",
            "--offline",
            "-vvv"
        ],
        timeout=TEST_TIMEOUT
    )

else:

    final_test_rc = 1

    print(
        "⚠️ Build failed.",
        flush=True
    )

    print(
        "Tests are NOT considered successful.",
        flush=True
    )


# ============================================================
# FINAL FILE CHECK
# ============================================================

banner("📋 FINAL ARTIFACT CHECK")


progress_exists = PROGRESS_FILE.exists()

report_exists = FINAL_REPORT.exists()


print(
    f"AUDIT_PROGRESS.md      : "
    f"{'EXISTS' if progress_exists else 'MISSING'}",
    flush=True
)

print(
    f"FINAL_AUDIT_REPORT.md  : "
    f"{'EXISTS' if report_exists else 'MISSING'}",
    flush=True
)


# ============================================================
# CHECK STATUS: COMPLETE
# ============================================================

status_complete = False


if progress_exists:

    try:

        progress_text = PROGRESS_FILE.read_text(
            encoding="utf-8",
            errors="replace"
        )

        if "STATUS: COMPLETE" in progress_text:

            status_complete = True

    except Exception:
        status_complete = False


print(
    f"AUDIT STATUS COMPLETE : "
    f"{'YES' if status_complete else 'NO'}",
    flush=True
)


# ============================================================
# FINAL GIT STATE
# ============================================================

banner("🌿 FINAL GIT STATE")


if GIT:

    run_command(
        [GIT, "status", "--short"],
        timeout=30
    )

    run_command(
        [GIT, "log", "-3", "--oneline"],
        timeout=30
    )


# ============================================================
# SAFETY RESULT
# ============================================================

banner("🔒 BLOCKCHAIN SAFETY RESULT")


print(
    "RPC          : DISABLED",
    flush=True
)

print(
    "Deployment   : DISABLED",
    flush=True
)

print(
    "Broadcast    : DISABLED",
    flush=True
)

print(
    "Transactions : DISABLED",
    flush=True
)

print(
    "Live chain   : NOT TOUCHED BY THIS WRAPPER",
    flush=True
)

print(
    "Gas          : ZERO",
    flush=True
)

print(
    "Git push     : DISABLED",
    flush=True
)


# ============================================================
# FINAL DECISION
# ============================================================

banner("🏁 FINAL AUDIT DECISION")


all_conditions = (
    opencode_success
    and final_build_rc == 0
    and final_test_rc == 0
    and report_exists
    and progress_exists
    and status_complete
)


if all_conditions:

    print(
        "✅ ALL WRAPPER COMPLETION CONDITIONS PASSED.",
        flush=True
    )

    print(
        "✅ OpenCode completed.",
        flush=True
    )

    print(
        "✅ forge build --offline passed.",
        flush=True
    )

    print(
        "✅ forge test --offline -vvv passed.",
        flush=True
    )

    print(
        "✅ FINAL_AUDIT_REPORT.md exists.",
        flush=True
    )

    print(
        "✅ AUDIT_PROGRESS.md exists.",
        flush=True
    )

    print(
        "✅ AUDIT_PROGRESS.md says STATUS: COMPLETE.",
        flush=True
    )

    print(
        "\n🌳 LOCAL AUDIT COMPLETION CONDITIONS PASSED.",
        flush=True
    )

else:

    print(
        "⚠️ AUDIT NOT CERTIFIED COMPLETE.",
        flush=True
    )

    print(
        f"OpenCode success : {opencode_success}",
        flush=True
    )

    print(
        f"Last OpenCode RC : {last_opencode_rc}",
        flush=True
    )

    print(
        f"Build exit       : {final_build_rc}",
        flush=True
    )

    print(
        f"Test exit        : {final_test_rc}",
        flush=True
    )

    print(
        f"Final report     : {report_exists}",
        flush=True
    )

    print(
        f"Checkpoint       : {progress_exists}",
        flush=True
    )

    print(
        f"STATUS COMPLETE  : {status_complete}",
        flush=True
    )

    print(
        "\nReview AUDIT_PROGRESS.md and "
        "FINAL_AUDIT_REPORT.md.",
        flush=True
    )


print(
    "\n🌳 Arizona Forestation DAO audit wrapper finished.",
    flush=True
)
