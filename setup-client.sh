#!/bin/bash
# =============================================================
# NeuroFL Client Node Setup
# =============================================================
# One script for all platforms. Run once per machine.
#
# Linux:     curl -sSL https://raw.githubusercontent.com/Brain-Institute/cfa-neurofl-client-setup-script/main/setup-client.sh -o setup-client.sh && sudo bash setup-client.sh <site>-onboarding.tar.gz
# Mac:       curl -sSL https://raw.githubusercontent.com/Brain-Institute/cfa-neurofl-client-setup-script/main/setup-client.sh -o setup-client.sh && bash setup-client.sh <site>-onboarding.tar.gz
# Windows:   Open WSL terminal, then run the Linux command above
# =============================================================
set -e

OS="$(uname -s)"
IS_WSL=false
if grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=true
fi

echo ""
echo "============================================"
echo "  NeuroFL Client Node Setup"
echo "============================================"
echo ""
if [ "$IS_WSL" = true ]; then
    echo "Detected: Windows (WSL)"
elif [ "$OS" = "Darwin" ]; then
    echo "Detected: macOS"
else
    echo "Detected: Linux"
fi
echo ""

# -------------------------------------------------------
# Load the onboarding bundle (replaces manual token/VM entry)
# -------------------------------------------------------
# The OBI-generated bundle carries ca.crt + <site>.key + config.env. Everything
# that used to be typed in (token, VM name, server) — plus the new SuperLink
# address and cert paths — now comes from config.env inside the bundle.

BUNDLE_PATH=""
ACCEPT_LICENSE=false
for arg in "$@"; do
    case "$arg" in
        --accept-license) ACCEPT_LICENSE=true ;;
        -*)               echo "Unknown option: $arg" >&2; exit 1 ;;
        *)                [ -z "$BUNDLE_PATH" ] && BUNDLE_PATH="$arg" ;;
    esac
done

if [ -z "$BUNDLE_PATH" ] || [ ! -f "$BUNDLE_PATH" ]; then
    echo "Usage: bash setup-client.sh [--accept-license] <site>-onboarding.tar.gz"
    echo "Error: onboarding bundle not found."
    exit 1
fi

# -------------------------------------------------------
# Prerequisites — check BEFORE we ask anyone to accept a licence
# -------------------------------------------------------
# Fresh cloud VMs (GCP/AWS/Azure images) usually do NOT ship Docker. Without this
# check the script would run all the way through the EULA and setup, then fail
# with an opaque "docker: command not found" — so fail early and say what to do.
if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker is not installed on this machine." >&2
    echo "" >&2
    echo "  The NeuroFL client runs as a Docker container. Install Docker first:" >&2
    echo "" >&2
    echo "    # Debian / Ubuntu (incl. most GCP, AWS and Azure images):" >&2
    echo "    curl -fsSL https://get.docker.com | sudo sh" >&2
    echo "" >&2
    echo "  Then re-run this script." >&2
    exit 1
fi

# Docker present but the daemon isn't reachable (not started, or the user isn't
# allowed to talk to it) — another very common first-run stumble on a new VM.
if ! docker info >/dev/null 2>&1 && ! sudo docker info >/dev/null 2>&1; then
    echo "Error: Docker is installed but the daemon is not reachable." >&2
    echo "" >&2
    echo "  Start it, then re-run this script:" >&2
    echo "    sudo systemctl enable --now docker" >&2
    echo "" >&2
    echo "  (If it is running, you may need to run this script with sudo.)" >&2
    exit 1
fi

# -------------------------------------------------------
# Bundle extraction — tolerate an already-decompressed download
# -------------------------------------------------------
# Some browsers and download services (e.g. an Azure SAS link) transparently
# gunzip a .tar.gz while KEEPING the .tar.gz name. `tar -xzf` then dies with
#   "gzip: stdin: not in gzip format"
# which is confusing and has burned sites before. So: sniff the actual file type
# and extract accordingly, instead of trusting the extension.
extract_bundle() {   # extract_bundle <dest-dir>
    _dest="$1"
    if gzip -t "$BUNDLE_PATH" >/dev/null 2>&1; then
        tar -xzf "$BUNDLE_PATH" -C "$_dest"          # real .tar.gz
    elif tar -tf "$BUNDLE_PATH" >/dev/null 2>&1; then
        tar -xf  "$BUNDLE_PATH" -C "$_dest"          # plain .tar (was decompressed in transit)
    else
        return 1
    fi
}

# Validate the bundle up front so a bad download fails with a clear message
# rather than a cryptic gzip/tar error deep in the install.
if ! extract_bundle "$(mktemp -d)" >/dev/null 2>&1; then
    echo "Error: '$BUNDLE_PATH' is not a readable onboarding bundle." >&2
    echo "" >&2
    echo "  It is neither a valid .tar.gz nor a plain .tar archive. This usually" >&2
    echo "  means the download was corrupted or incomplete." >&2
    echo "" >&2
    echo "  What it actually looks like:" >&2
    echo "    $(file -b "$BUNDLE_PATH" 2>/dev/null || echo 'unknown file type')" >&2
    echo "    size: $(wc -c < "$BUNDLE_PATH" 2>/dev/null || echo '?') bytes" >&2
    echo "" >&2
    echo "  Re-download the bundle and try again. Do not open/re-save it with an" >&2
    echo "  archive tool in between — transfer it as-is." >&2
    exit 1
fi

# -------------------------------------------------------
# End User License Agreement — must be accepted BEFORE we install anything
# -------------------------------------------------------
# The NeuroFL Node software is licensed by the Ontario Brain Institute under a
# EULA. Nothing is installed (no image pulled, no container started, no secrets
# written to disk) until the operator explicitly accepts it.
#
# The agreement text is EMBEDDED below rather than fetched or read from the
# bundle. Operators always curl this script fresh, so embedding means the gate
# works for every client — including sites whose onboarding bundle predates the
# EULA — and on offline/air-gapped hosts. If a (newer) LICENSE.md is present in
# the onboarding bundle it takes precedence, so a revised agreement shipped with
# a new bundle supersedes the copy baked in here.
LICENSE_FILE="$(mktemp)"
LICENSE_SOURCE="embedded in setup-client.sh"

cat > "$LICENSE_FILE" <<'NEUROFL_EULA_END'
END USER LICENSE AGREEMENT ("EULA")   

Software: NeuroFL Node (also known as "NeuroFL Client")

Node Licensor: Ontario Brain Institute (“OBI”) 

0. Background 

You desire to upload certain proprietary software, created and owned by OBI.  This is referred to internally as the NeuroFL Node software or, for the purposes of this Agreement, the “Software”, and includes all iterations of that that software, as amended, updated modified for replaced from time to time.  While certain aspects of the Software are installed on your local network, the Software is primarily installed and operated through a cloud server operated by or on behalf of OBI (the “NeuroFL Server”).   While not the exclusive use case, and without limiting potential use cases going forward, it is contemplated that you will upload certain aspects of the Software onto your local computer network, and in connection with various research projects that exist from time to time, it is anticipated that you will upload data (“Data”) to your computer network through the interface of the Software, or accessible by the Software.  During the time that parts of the Software are installed on your computer network or you have access to the Software and the NeuroFL Server, your computer network is referred to a “NeuroFL Node”.   In consultation between OBI and you (the “Consultation Process”), various parties (“Modelers”) may be given access to the Data for the purpose of running and training AI models (the “AI Models”), with all work product so produced by the Modeler or derived from the AI models from time to time referred to as the “AI Work Product”.  The current intention in creating and implementing the Software, is to create a number of NeuroFL Nodes, that may be accessed by the AI Models of the Modelers in order to improve the understanding of brain disorders and support brain health in keeping with OBI’s mission statement and objectives.   The collection of NeuroFL Nodes existing from time to time and managed by OBI is referred to as the “NeuroFL Federated Learning Network”. 

1. License Grant 

OBI ("Licensor") grants you ("Licensee") a non-exclusive, non-transferable, revocable license to use the Software solely for the purpose of participating in the NeuroFL Federated Learning Network and implementing a NeuroFL Node to enable the training of analysis models or AI Models designed by a Modeler (the “Permitted Purpose”). 

Requirements for Operation:  

The NeuroFL Node must connect to the NeuroFL Server and maintain a secure connection with that server to function and accomplish its tasks. Any disruption or failure to maintain this secure connection may result in the NeuroFL Node being unable to participate in the NeuroFL Federated Learning Network, or otherwise not properly functioning. 

2. Ownership and Intellectual Property 

The Software and all intellectual property rights in the Software are and shall remain the exclusive property of OBI. Any open-source components included in the Software are owned by their respective rightful creators and are subject to their applicable open-source licenses. 

All intellectual property rights in the AI Models, and the AI Work Product remain the sole property of the Modeler who created the AI Model. The Licensee does not acquire any ownership rights to the AI Models or the AI Work Product by using the Software and participating in the NeuroFL Federated Learning Network. 

3. Additional User Obligations 

* You agree to use the Software in compliance with all applicable laws and regulations. 

* You must not interfere with or disrupt the NeuroFL Federated Learning Network or other users' access to the Software. 

* You must comply with all terms of this EULA and any project agreement with OBI existing from time to time. 

* You may not modify, reverse engineer, decompile, disassemble, or create derivative works of the Software. 

* You may not redistribute, sublicense, or transfer the Software to any third party. 

* You may not use the Software for any illegal or unauthorized purpose. 

* You shall not upload Data accessible to the AI Models where such access or use by the Modeler or AI Model is prohibited by agreements that you have with third parties, is otherwise prohibited, or is contrary to what was agreed in the Consultation Process. 

* You shall not grant access to the Software to any person or entity, other than your employees, or persons employed by the entity that you are employed by, provided (a) that any such access shall be solely for the Purpose and (b) that such person shall be bound by the terms of this EULA. 

4. Limitations of Liability 

Disclaimer of Warranties: THE SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT. 

No Liability: IN NO EVENT SHALL OBI OR ITS DEVELOPERS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR EXEMPLARY DAMAGES ARISING OUT OF OR IN ANY WAY RELATED TO THE USE OF THE SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES. 

5. Termination 

This license is effective until terminated. OBI may terminate this license immediately upon written request if you breach any term of this EULA, or upon completion of any project agreement with OBI or at any time by notice to you, which may be given at will. You may terminate this license at any time by ceasing use of the Software and uninstalling it from all devices. Upon termination, you must immediately cease all use of the Software, destroy all copies in your possession and cease connection with the NeuroFL Server.  Sections 2, 3, 4, 5, 6, 8 and 9 survive termination of this EULA. 

6. Privacy Policy 

The Software collects NeuroFL Node activity log data and training data during training rounds and from time to time. Both the activity log data, training data, and other model parameters are transferred to the central NeuroFL Server for operational purposes. No other Data is collected, stored, or transferred. The Licensee remains the custodian and/or owner of all Data, except for Data expressly transferred as described above and except for AI Work Product.  

7. Updates and Maintenance 

OBI may provide updates or maintenance for the Software at its sole discretion. You are not entitled to receive any updates or support, and OBI is under no obligation to provide them. 

8. Governing Law and Dispute Resolution 

This EULA shall be governed by and construed in accordance with the laws of the Province of Ontario, Canada. Any disputes arising under or in connection with this EULA shall be resolved exclusively in the courts of Ontario. 

9. Miscellaneous Provisions 

Severability: If any provision of this EULA is found to be unenforceable, the remaining provisions shall remain in full force and effect. 

Entire Agreement: This EULA constitutes the entire agreement between you and OBI regarding the use of the Software. 

Amendments: OBI reserves the right to amend this EULA at any time upon notice to you, which notice may be in a form considered reasonable by OBI. Continued use of the Software after such amendments constitutes acceptance of the revised terms. 

10. Acceptance of Terms 

By installing or using the Software, you acknowledge that you have read this EULA, understand it, and agree to be bound by its terms and conditions. If you do not agree to these terms, do not install or use the Software. 

 

Effective Date: January 30, 2026

Contact Information: For questions or concerns regarding this EULA, please contact OBI at informatics@braininstitute.ca. 
NEUROFL_EULA_END

# A LICENSE.md inside the onboarding bundle (newer bundles carry one) wins.
LIC_TMP="$(mktemp -d)"
extract_bundle "$LIC_TMP" >/dev/null 2>&1 || true
BUNDLED_LICENSE="$(find "$LIC_TMP" -iname 'LICENSE*' -type f | head -n1)"
if [ -n "$BUNDLED_LICENSE" ] && [ -s "$BUNDLED_LICENSE" ]; then
    cp "$BUNDLED_LICENSE" "$LICENSE_FILE"
    LICENSE_SOURCE="onboarding bundle ($(basename "$BUNDLED_LICENSE"))"
fi
rm -rf "$LIC_TMP"

if [ ! -s "$LICENSE_FILE" ]; then
    echo "Error: the End User License Agreement could not be loaded." >&2
    rm -f "$LICENSE_FILE"
    exit 1
fi

if [ "$ACCEPT_LICENSE" = true ]; then
    echo "End User License Agreement: accepted via --accept-license (source: $LICENSE_SOURCE)."
    echo ""
else
    # Read the operator's answer from the terminal. Prefer /dev/tty so the prompt
    # still works when the script itself was piped in (curl | bash); fall back to
    # stdin. If we have NO interactive input at all we must NOT fail open — a
    # license gate that silently passes is worse than useless — so we stop and
    # tell the operator to re-run with --accept-license.
    # Pick where to read the operator's answer from:
    #   1. A real terminal (/dev/tty) — works even when the script itself was
    #      piped in (curl ... | bash). Must be genuinely openable: in some
    #      containers/cron/CI the path exists but errors on open.
    #   2. Otherwise stdin, if something is actually connected (a tty, or a pipe
    #      such as `printf 'I AGREE' | bash setup-client.sh bundle.tar.gz`).
    #   3. Otherwise there is no way to ask -> FAIL CLOSED. A license gate that
    #      silently passes when it cannot prompt is worse than no gate at all.
    if (exec 3< /dev/tty) 2>/dev/null; then
        exec 3< /dev/tty
    elif [ -t 0 ] || [ -p /dev/stdin ] || [ ! -t 0 ]; then
        exec 3<&0
    else
        echo "Error: the End User License Agreement must be accepted before installing," >&2
        echo "       but this session has no terminal or input to prompt on." >&2
        echo "" >&2
        echo "       Review LICENSE.md in your onboarding bundle, then re-run with:" >&2
        echo "         bash setup-client.sh --accept-license $BUNDLE_PATH" >&2
        rm -f "$LICENSE_FILE"
        exit 1
    fi

    echo "============================================"
    echo "  End User License Agreement"
    echo "============================================"
    echo ""
    echo "Before installing the NeuroFL Node software you must read and accept"
    echo "the Ontario Brain Institute End User License Agreement, reproduced in"
    echo "full below."
    echo ""
    printf "Press Enter to display the full agreement... "
    read -r _ <&3 || true
    echo ""
    echo "============================================================"
    # Print the WHOLE agreement to the terminal. We deliberately do NOT use a
    # pager here: with `less` the operator can quit part-way (people were only
    # seeing up to section 2) and the rest of a legally binding agreement would
    # never be shown. Printing it in full puts every clause in the scrollback.
    cat "$LICENSE_FILE"
    echo "============================================================"
    echo "                (end of agreement)"
    echo ""
    echo "Source: $LICENSE_SOURCE"
    echo "Scroll up to review the full text before answering."
    echo ""
    echo "By typing 'I AGREE' you confirm that you have read, understood, and"
    echo "accept the End User License Agreement on behalf of your institution,"
    echo "and that you are authorized to do so."
    echo ""
    printf "Type 'I AGREE' to accept, or anything else to cancel: "
    LICENSE_ANSWER=""
    read -r LICENSE_ANSWER <&3 || true
    exec 3<&-
    case "$(printf '%s' "$LICENSE_ANSWER" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')" in
        IAGREE) ;;
        *)
            echo ""
            echo "License not accepted. Installation cancelled — nothing was installed."
            rm -f "$LICENSE_FILE"
            exit 1
            ;;
    esac
    echo ""
    echo "License accepted. Continuing with installation..."
    echo ""
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" "$LICENSE_FILE"' EXIT
extract_bundle "$WORK"

CONFIG_ENV_SRC="$(find "$WORK" -name config.env -type f | head -n1)"
if [ -z "$CONFIG_ENV_SRC" ]; then
    echo "Error: config.env not found inside the bundle."
    exit 1
fi
BUNDLE_SRC="$(dirname "$CONFIG_ENV_SRC")"

# Pull just the scalars we need for display + path derivation. We deliberately
# do NOT `source` config.env: Docker passes it verbatim via --env-file, and
# values like NODE_CONFIG ('site="x" sandbox.resources="y"') contain spaces and
# quotes that would break shell sourcing.
cfg() { grep -E "^$1=" "$CONFIG_ENV_SRC" | head -n1 | cut -d= -f2-; }
VM_NAME="$(cfg VM_NAME)"
SUPERLINK_ADDRESS="$(cfg SUPERLINK_ADDRESS)"
FL_SERVER_URL="$(cfg FL_SERVER_URL)"
API_TOKEN="$(cfg API_TOKEN)"
ROOT_CERTIFICATES="$(cfg ROOT_CERTIFICATES)"
SUPERNODE_PRIVATE_KEY="$(cfg SUPERNODE_PRIVATE_KEY)"

for required in VM_NAME SUPERLINK_ADDRESS ROOT_CERTIFICATES SUPERNODE_PRIVATE_KEY; do
    if [ -z "${!required}" ]; then
        echo "Error: config.env is missing $required."
        exit 1
    fi
done

# Derive cert/key filenames from the container paths config.env declares, so the
# bundle and the run command can never disagree on names.
CA_BASENAME="$(basename "$ROOT_CERTIFICATES")"
KEY_BASENAME="$(basename "$SUPERNODE_PRIVATE_KEY")"

if [ ! -f "$BUNDLE_SRC/$CA_BASENAME" ] || [ ! -f "$BUNDLE_SRC/$KEY_BASENAME" ]; then
    echo "Error: bundle is missing $CA_BASENAME or $KEY_BASENAME."
    exit 1
fi

# -------------------------------------------------------
# Host paths (the only thing still asked locally)
# -------------------------------------------------------
if [ "$IS_WSL" = true ]; then
    DEFAULT_DATA_DIR="/mnt/c/fl-data"
    DEFAULT_LOGS_DIR="/mnt/c/fl-logs"
elif [ "$OS" = "Darwin" ]; then
    DEFAULT_DATA_DIR="$HOME/fl-data"
    DEFAULT_LOGS_DIR="$HOME/fl-logs"
else
    DEFAULT_DATA_DIR="/data/data-fl"
    DEFAULT_LOGS_DIR="$HOME/fl-logs"
fi

read -p "Data directory path [$DEFAULT_DATA_DIR]: " DATA_DIR
DATA_DIR="${DATA_DIR:-$DEFAULT_DATA_DIR}"

read -p "Logs directory path [$DEFAULT_LOGS_DIR]: " LOGS_DIR
LOGS_DIR="${LOGS_DIR:-$DEFAULT_LOGS_DIR}"

echo ""
echo "--------------------------------------------"
echo "  Configuration (from bundle)"
echo "--------------------------------------------"
echo "  VM Name:        $VM_NAME"
echo "  SuperLink:      $SUPERLINK_ADDRESS"
echo "  REST API:       ${FL_SERVER_URL:-n/a}"
echo "  API Token:      ${API_TOKEN:0:8}..."
echo "  Fleet CA:       $CA_BASENAME"
echo "  Private key:    $KEY_BASENAME"
echo "  Data Dir:       $DATA_DIR"
echo "  Logs Dir:       $LOGS_DIR"
echo "--------------------------------------------"
echo ""
read -p "Proceed? [Y/n]: " CONFIRM
CONFIRM="${CONFIRM:-Y}"
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""

# -------------------------------------------------------
# Create directories
# -------------------------------------------------------

mkdir -p "$DATA_DIR" "$LOGS_DIR"
echo "  Created: $DATA_DIR"
echo "  Created: $LOGS_DIR"

# -------------------------------------------------------
# Config dir + bundle secrets (all platforms)
# -------------------------------------------------------

if [ "$OS" = "Linux" ] && [ "$IS_WSL" = false ]; then
    CONFIG_DIR="/opt/fl-client"
else
    CONFIG_DIR="$HOME/.neurofl"
fi
mkdir -p "$CONFIG_DIR"

# Record the EULA acceptance for auditability: who accepted it, when, on which
# host, and a hash of the exact text they accepted (so we can prove which
# version was agreed to if the agreement is later revised).
LICENSE_SHA="$( (sha256sum "$LICENSE_FILE" 2>/dev/null || shasum -a 256 "$LICENSE_FILE" 2>/dev/null) | awk '{print $1}' )"
cp "$LICENSE_FILE" "$CONFIG_DIR/LICENSE.accepted.md" 2>/dev/null || true
cat > "$CONFIG_DIR/license-acceptance.txt" <<EOF
NeuroFL Node — End User License Agreement acceptance
accepted_at:    $(date -u '+%Y-%m-%dT%H:%M:%SZ')
accepted_by:    ${SUDO_USER:-${USER:-unknown}}
host:           $(hostname 2>/dev/null || echo unknown)
license_source: $LICENSE_SOURCE
license_sha256: ${LICENSE_SHA:-unavailable}
method:         $([ "$ACCEPT_LICENSE" = true ] && echo "--accept-license flag" || echo "interactive (typed I AGREE)")
EOF
chmod 644 "$CONFIG_DIR/license-acceptance.txt" 2>/dev/null || true

# Install the bundle's secrets next to the run command (kept for restarts).
cp "$BUNDLE_SRC/$CA_BASENAME"  "$CONFIG_DIR/$CA_BASENAME"
cp "$BUNDLE_SRC/$KEY_BASENAME" "$CONFIG_DIR/$KEY_BASENAME"
cp "$CONFIG_ENV_SRC"           "$CONFIG_DIR/config.env"

# Ensure runtime dependency installation is enabled. The ClientApp declares its
# deps (torch, numpy, ...) in pyproject.toml; with this on, the SuperNode runs
# `uv sync` to install them per task. Without it, apps fail with
# ModuleNotFoundError. Force it here so the client works even if the bundle's
# config.env predates this setting.
if grep -qE "^ALLOW_RUNTIME_DEPENDENCY_INSTALLATION=" "$CONFIG_DIR/config.env"; then
    sed -i 's/^ALLOW_RUNTIME_DEPENDENCY_INSTALLATION=.*/ALLOW_RUNTIME_DEPENDENCY_INSTALLATION=true/' "$CONFIG_DIR/config.env"
else
    echo "ALLOW_RUNTIME_DEPENDENCY_INSTALLATION=true" >> "$CONFIG_DIR/config.env"
fi

chmod 600 "$CONFIG_DIR/$KEY_BASENAME" "$CONFIG_DIR/config.env"
chmod 644 "$CONFIG_DIR/$CA_BASENAME"

# The container drops to fluser (UID 1000). When this script runs under sudo
# (the Linux production path), the copies above land as root:root — a 600 key
# owned by root is unreadable to UID 1000, so SuperNode crashes with EACCES.
# Re-own the key to UID 1000 so the bind mount is readable inside the container.
# Gated on running-as-root so it's a no-op on Mac/WSL (no sudo, no privilege
# to chown), where Docker Desktop's mount layer already handles UID mapping.
if [ "$(id -u)" -eq 0 ]; then
    chown 1000:1000 "$CONFIG_DIR/$KEY_BASENAME"
fi

echo "  Secrets installed in $CONFIG_DIR"

# -------------------------------------------------------
# Outer Docker seccomp profile — required by nsjail (NOT bwrap) on every
# platform. It permits the namespace/mount syscalls nsjail uses to build its
# inner sandbox. The inner nsjail policy is a separate file shipped in the image.
# -------------------------------------------------------
cat > "$CONFIG_DIR/seccomp-profile.json" << 'SECCOMP_EOF'
{
    "defaultAction": "SCMP_ACT_ERRNO",
    "defaultErrnoRet": 1,
    "archMap": [
        {
            "architecture": "SCMP_ARCH_X86_64",
            "subArchitectures": ["SCMP_ARCH_X86", "SCMP_ARCH_X32"]
        },
        {
            "architecture": "SCMP_ARCH_AARCH64",
            "subArchitectures": ["SCMP_ARCH_ARM"]
        }
    ],
    "syscalls": [
        {
            "names": [
                "accept", "accept4", "access", "arch_prctl", "bind", "brk", "capget",
                "capset", "chdir", "chmod", "chown", "chown32", "clock_getres",
                "clock_gettime", "clock_nanosleep", "close", "close_range", "connect",
                "copy_file_range", "creat", "dup", "dup2", "dup3", "epoll_create",
                "epoll_create1", "epoll_ctl", "epoll_ctl_old", "epoll_pwait",
                "epoll_pwait2", "epoll_wait", "epoll_wait_old", "eventfd",
                "eventfd2", "execve", "execveat", "exit", "exit_group", "faccessat",
                "faccessat2", "fadvise64", "fadvise64_64", "fallocate",
                "fanotify_mark", "fchdir", "fchmod", "fchmodat", "fchown",
                "fchown32", "fchownat", "fcntl", "fcntl64", "fdatasync",
                "fgetxattr", "flistxattr", "flock", "fork", "fremovexattr",
                "fsetxattr", "fstat", "fstat64", "fstatat64", "fstatfs",
                "fstatfs64", "fsync", "ftruncate", "ftruncate64", "futex",
                "futex_waitv", "futimesat", "getcpu", "getcwd", "getdents",
                "getdents64", "getegid", "getegid32", "geteuid", "geteuid32",
                "getgid", "getgid32", "getgroups", "getgroups32", "getitimer",
                "getpeername", "getpgid", "getpgrp", "getpid", "getppid",
                "getpriority", "getrandom", "getresgid", "getresgid32",
                "getresuid", "getresuid32", "getrlimit", "get_robust_list",
                "getrusage", "getsid", "getsockname", "getsockopt",
                "get_thread_area", "gettid", "gettimeofday", "getuid",
                "getuid32", "getxattr", "inotify_add_watch", "inotify_init",
                "inotify_init1", "inotify_rm_watch", "io_cancel", "ioctl",
                "io_destroy", "io_getevents", "io_pgetevents", "ioprio_get",
                "ioprio_set", "io_setup", "io_submit", "io_uring_enter",
                "io_uring_register", "io_uring_setup", "ipc", "kill",
                "landlock_add_rule", "landlock_create_ruleset",
                "landlock_restrict_self", "lchown", "lchown32", "lgetxattr",
                "link", "linkat", "listen", "listxattr", "llistxattr",
                "_llseek", "lremovexattr", "lseek", "lsetxattr", "lstat",
                "lstat64", "madvise", "membarrier", "memfd_create",
                "memfd_secret", "mincore", "mkdir", "mkdirat", "mknod",
                "mknodat", "mlock", "mlock2", "mlockall", "mmap", "mmap2",
                "mprotect", "mq_getsetattr", "mq_notify", "mq_open",
                "mq_timedreceive", "mq_timedsend", "mq_unlink", "mremap",
                "msgctl", "msgget", "msgrcv", "msgsnd", "msync", "munlock",
                "munlockall", "munmap", "name_to_handle_at", "nanosleep",
                "newfstatat", "_newselect", "open", "openat", "openat2",
                "pause", "pidfd_open", "pidfd_send_signal", "pipe", "pipe2",
                "poll", "ppoll", "prctl", "pread64", "preadv", "preadv2",
                "prlimit64", "process_mrelease", "pselect6", "ptrace",
                "pwrite64", "pwritev", "pwritev2", "read", "readahead",
                "readlink", "readlinkat", "readv", "recv", "recvfrom",
                "recvmmsg", "recvmsg", "remap_file_pages", "removexattr",
                "rename", "renameat", "renameat2", "restart_syscall",
                "rmdir", "rseq", "rt_sigaction", "rt_sigpending",
                "rt_sigprocmask", "rt_sigqueueinfo", "rt_sigreturn",
                "rt_sigsuspend", "rt_sigtimedwait", "rt_tgsigqueueinfo",
                "sched_getaffinity", "sched_getattr", "sched_getparam",
                "sched_get_priority_max", "sched_get_priority_min",
                "sched_getscheduler", "sched_rr_get_interval",
                "sched_setaffinity", "sched_setattr", "sched_setparam",
                "sched_setscheduler", "sched_yield", "seccomp", "select",
                "semctl", "semget", "semop", "semtimedop", "send", "sendfile",
                "sendfile64", "sendmmsg", "sendmsg", "sendto", "setfsgid",
                "setfsgid32", "setfsuid", "setfsuid32", "setgid", "setgid32",
                "setgroups", "setgroups32", "setitimer", "setpgid",
                "setpriority", "setregid", "setregid32", "setresgid",
                "setresgid32", "setresuid", "setresuid32", "setreuid",
                "setreuid32", "setrlimit", "set_robust_list", "setsid",
                "setsockopt", "set_thread_area", "set_tid_address",
                "setuid", "setuid32", "setxattr", "shmat", "shmctl",
                "shmdt", "shmget", "shutdown", "sigaltstack", "signalfd",
                "signalfd4", "sigprocmask", "sigreturn", "socket",
                "socketcall", "socketpair", "splice", "stat", "stat64",
                "statfs", "statfs64", "statx", "symlink", "symlinkat",
                "sync", "sync_file_range", "syncfs", "sysinfo", "tee",
                "tgkill", "time", "timer_create", "timer_delete",
                "timer_getoverrun", "timer_gettime", "timer_gettime64",
                "timer_settime", "timer_settime64", "timerfd_create",
                "timerfd_gettime", "timerfd_gettime64", "timerfd_settime",
                "timerfd_settime64", "times", "tkill", "truncate",
                "truncate64", "ugetrlimit", "umask", "uname", "unlink",
                "unlinkat", "utime", "utimensat", "utimensat_time64",
                "utimes", "vfork", "vmsplice", "wait4", "waitid",
                "waitpid", "write", "writev"
            ],
            "action": "SCMP_ACT_ALLOW"
        },
        {
            "names": [
                "clone", "clone3", "unshare", "setns",
                "mount", "umount", "umount2", "pivot_root", "chroot"
            ],
            "action": "SCMP_ACT_ALLOW",
            "comment": "Required for nsjail to create its inner mount/user namespace inside the container"
        },
        {
            "names": ["personality"],
            "action": "SCMP_ACT_ALLOW",
            "args": [{ "index": 0, "value": 0, "op": "SCMP_CMP_EQ" }]
        }
    ]
}
SECCOMP_EOF
chmod 644 "$CONFIG_DIR/seccomp-profile.json"
echo "  Seccomp profile installed (nsjail outer policy)"

# -------------------------------------------------------
# Inner nsjail app-sandbox policy + host-backed caches
# -------------------------------------------------------
# The ClientApp installs its own deps at run time (uv sync: torch, numpy, ...).
# Flower's PACKAGED nsjail profile mounts /root/.cache and /root/.flwr as a 1 GB
# tmpfs (RAM) — torch+CUDA wheels extract to several GB and overflow it with
# "No space left on device". This custom profile binds those caches to the host
# filesystem instead, so large installs land on disk. We point SuperExec at it
# via FLWR_SUPEREXEC_SANDBOX_CONFIG below.
cat > "$CONFIG_DIR/nsjail.cfg" << 'NSJAIL_EOF'
name: "flower-app"
mode: ONCE
cwd: "/tmp"
time_limit: 0

clone_newnet: false
clone_newuser: true
clone_newns: true
clone_newpid: true
clone_newipc: true
clone_newuts: false
clone_newcgroup: false

keep_env: true
keep_caps: false

rlimit_cpu: 3600
rlimit_fsize: 2048
rlimit_nofile: 4096
rlimit_nproc: 1024
rlimit_memlock: 67108864

seccomp_string: "DEFAULT ALLOW"

mount {
  src: "/"
  dst: "/"
  is_bind: true
  rw: false
}

mount {
  dst: "/tmp"
  fstype: "tmpfs"
  rw: true
  options: "size=1073741824"
  nosuid: true
  nodev: true
}

mount {
  dst: "/dev/shm"
  fstype: "tmpfs"
  rw: true
  options: "size=4294967296"
  nosuid: true
  nodev: true
}

# Host-backed bind mounts for FAB install + uv cache. tmpfs needs RAM, and
# torch+CUDA wheels need several GB which exceeds the 1 GB packaged-profile
# tmpfs. Backed by the host filesystem (/host-cache/*) instead.
mount {
  src: "/host-cache/flwr"
  dst: "/root/.flwr"
  is_bind: true
  rw: true
}

mount {
  src: "/host-cache/cache"
  dst: "/root/.cache"
  is_bind: true
  rw: true
}

mount {
  dst: "/root/.config"
  fstype: "tmpfs"
  rw: true
  options: "size=67108864"
  nosuid: true
  nodev: true
}

mount {
  src: "/proc"
  dst: "/proc"
  is_bind: true
  rw: false
  nosuid: true
  nodev: true
}

# Optional GPU device nodes (skipped on CPU-only hosts).
mount {
  src: "/dev/nvidiactl"
  dst: "/dev/nvidiactl"
  is_bind: true
  rw: true
  mandatory: false
  is_dir: false
}

mount {
  src: "/dev/nvidia-uvm"
  dst: "/dev/nvidia-uvm"
  is_bind: true
  rw: true
  mandatory: false
  is_dir: false
}

mount {
  src: "/dev/nvidia-uvm-tools"
  dst: "/dev/nvidia-uvm-tools"
  is_bind: true
  rw: true
  mandatory: false
  is_dir: false
}

mount {
  src: "/dev/nvidia0"
  dst: "/dev/nvidia0"
  is_bind: true
  rw: true
  mandatory: false
  is_dir: false
}
NSJAIL_EOF
chmod 644 "$CONFIG_DIR/nsjail.cfg"
echo "  nsjail app-sandbox profile installed (inner policy, host-backed caches)"

# Host-backed cache dirs the nsjail profile binds in. Sized for torch+CUDA wheels
# (several GB) which would overflow the packaged 1 GB tmpfs.
#
# OWNERSHIP MUST MATCH THE CONTAINER USER. The container now runs as root
# (--user 0:0, required so nsjail can build its mount tree — see SECURITY_FLAGS),
# and nsjail maps that root straight through (inside_uid:0 -> outside_uid:0, no
# uidmap). So the sandboxed ClientApp writes these host-bound dirs as UID 0, and
# they must be root-owned. If they are left owned by UID 1000 (the old fluser
# design), the sandbox — root across the userns boundary — CANNOT write a
# 1000-owned, 0755 dir, and every round fails with:
#   PermissionError: [Errno 13] Permission denied: '/root/.flwr/apps/<fab>...'
# -> "Received 0 results and N failures", final tensors=0, empty model.
#
# Pre-create flwr/apps and flwr/runtime-envs so the very first FAB install has a
# writable target, and force root ownership even over a stale 1000-owned apps/
# left by a pre-fix install.
HOST_CACHE_DIR="/var/lib/flwr-cache/${VM_NAME}"
mkdir -p "$HOST_CACHE_DIR/cache" \
         "$HOST_CACHE_DIR/flwr/apps" \
         "$HOST_CACHE_DIR/flwr/runtime-envs"
chown -R 0:0 "$HOST_CACHE_DIR" || {
    echo "  WARNING: could not chown $HOST_CACHE_DIR to root — FAB installs" >&2
    echo "           inside the nsjail sandbox may fail with PermissionError." >&2
}
chmod -R u+rwX "$HOST_CACHE_DIR"
echo "  Host-backed dependency cache ready at $HOST_CACHE_DIR (flwr/apps writable by container root)"

# Per-dataset SuperNode identities (multi-dataset enrollment). When a site adds
# more than one dataset, each dataset beyond the first gets its own generated
# keypair, enrolled live via {FL_SERVER_URL}/supernodes/register. Those keys +
# node_ids MUST persist across container recreation (keys are unique server-side
# and cannot be re-registered), so store them on a host-mounted dir owned by the
# container's UID 1000. The first dataset reuses the bundle's pre-registered key.
IDENTITIES_DIR="${CONFIG_DIR}/identities"
mkdir -p "$IDENTITIES_DIR"
chown -R 1000:1000 "$IDENTITIES_DIR" 2>/dev/null || true
echo "  SuperNode identities dir ready at $IDENTITIES_DIR"

# nsjail sandbox requirements — ALL of these are mandatory, and getting any one
# wrong makes the inner sandbox fail with:
#   mount('/', MS_REC|MS_PRIVATE): Permission denied
#
# nsjail creates a new user namespace with no uidmap, so the sandboxed process
# is mapped straight through to the container's own UID. For the mandatory
# mount('/', MS_PRIVATE) inside that namespace to succeed, the container must
# run as UID 0 (--user 0:0) AND retain CAP_SYS_ADMIN in its bounding set:
#   - As non-root (the image default, fluser/UID 1000), the sandbox lands
#     without CAP_SYS_ADMIN in the new userns and the mount is denied.
#   - Under `--cap-drop ALL`, even root can't write /proc/<pid>/uid_map, so the
#     namespace never initializes.
# So: run as root and DO NOT cap-drop. nsjail is what isolates the workload;
# the outer container being root only provides the capabilities nsjail needs.
# (The image runs supervisord with no per-program user=, so root is fine; the
# host-side data/cache dirs are owned by UID 1000 but root writes them freely.)
SECURITY_FLAGS="--user 0:0 --cap-add SYS_ADMIN --cap-add SETUID --cap-add SETGID --security-opt seccomp=$CONFIG_DIR/seccomp-profile.json"

# Linux-only host extras: AppArmor override (docker-default would block nsjail's
# mounts) and POSIX ACLs on data/logs. The container runs as root now, so it can
# write these regardless, but we keep the UID-1000 ACLs so files it creates stay
# accessible to the fluser-owned tooling and any non-root inspection.
if [ "$OS" = "Linux" ] && [ "$IS_WSL" = false ]; then
    SECURITY_FLAGS="$SECURITY_FLAGS --security-opt apparmor=unconfined"

    if ! command -v setfacl &> /dev/null; then
        apt-get update -qq && apt-get install -y -qq acl > /dev/null 2>&1
        echo "  ACL support installed"
    fi

    setfacl -R -m u:1000:rwx "$DATA_DIR"
    setfacl -R -d -m u:1000:rwx "$DATA_DIR"
    setfacl -R -m u:1000:rwx "$LOGS_DIR"
    setfacl -R -d -m u:1000:rwx "$LOGS_DIR"
    echo "  Container permissions set (UID 1000)"
fi

# -------------------------------------------------------
# Build the docker run command
# -------------------------------------------------------

IMAGE="daccacrneurofed.azurecr.io/fl-client:latest"

DOCKER_CMD="docker"
if [ "$OS" = "Linux" ] && [ "$IS_WSL" = false ]; then
    DOCKER_CMD="sudo docker"
fi

# Secrets + connection config come from the bundle: the two certs are mounted
# at the container paths config.env names, and --env-file supplies the rest
# (SUPERLINK_ADDRESS, ROOT_CERTIFICATES, SUPERNODE_PRIVATE_KEY, NODE_CONFIG,
# VM_NAME, API_TOKEN, FL_SERVER_URL, SUPERLINK_INSECURE=false).
RUN_CMD="$DOCKER_CMD run -d --name fl-client \
  --restart unless-stopped \
  ${SECURITY_FLAGS} \
  -p 8501:8501 \
  -v ${DATA_DIR}:/data \
  -v ${LOGS_DIR}:/app/logs \
  -v ${CONFIG_DIR}/${CA_BASENAME}:${ROOT_CERTIFICATES}:ro \
  -v ${CONFIG_DIR}/${KEY_BASENAME}:${SUPERNODE_PRIVATE_KEY}:ro \
  -v ${CONFIG_DIR}/nsjail.cfg:/etc/neurofl/nsjail.cfg:ro \
  -v ${HOST_CACHE_DIR}/cache:/host-cache/cache \
  -v ${HOST_CACHE_DIR}/flwr:/host-cache/flwr \
  -v ${IDENTITIES_DIR}:/app/config/identities \
  -e FLWR_SUPEREXEC_SANDBOX_CONFIG=/etc/neurofl/nsjail.cfg \
  -e SUPERNODE_IDENTITIES_DIR=/app/config/identities \
  --env-file ${CONFIG_DIR}/config.env \
  ${IMAGE}"

RUN_CMD=$(echo "$RUN_CMD" | sed 's/  */ /g')

# -------------------------------------------------------
# Save run-client.sh
# -------------------------------------------------------

SAVE_DIR="$CONFIG_DIR"
mkdir -p "$SAVE_DIR"

cat > "$SAVE_DIR/run-client.sh" << 'RUNEOF'
#!/bin/bash
# =============================================================
# NeuroFL Client Runner
# Pulls latest image, handles updates, starts the container.
# Generated by setup-client.sh — do not edit manually.
# =============================================================

DOCKER_CMD="__DOCKER_CMD__"
IMAGE="daccacrneurofed.azurecr.io/fl-client:latest"
CONTAINER="fl-client"

# config.env was installed next to this script by setup-client.sh.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_ENV="$SCRIPT_DIR/config.env"
cfg() { grep -E "^$1=" "$CONFIG_ENV" 2>/dev/null | head -n1 | cut -d= -f2-; }

echo ""
echo "=== NeuroFL Client ==="
echo ""

# ----- Step 1: Pull latest image -----
echo "Checking for updates..."

# Authenticate to the private ACR if pull credentials shipped in the bundle.
ACR_REGISTRY="$(cfg ACR_REGISTRY)"
ACR_REGISTRY="${ACR_REGISTRY:-${IMAGE%%/*}}"
ACR_PULL_USER="$(cfg ACR_PULL_USER)"
ACR_PULL_TOKEN="$(cfg ACR_PULL_TOKEN)"
if [ -n "$ACR_PULL_USER" ] && [ -n "$ACR_PULL_TOKEN" ]; then
    echo "Logging in to ${ACR_REGISTRY}..."
    echo "$ACR_PULL_TOKEN" | $DOCKER_CMD login "$ACR_REGISTRY" -u "$ACR_PULL_USER" --password-stdin
fi

OLD_IMAGE_ID=$($DOCKER_CMD images --format "{{.ID}}" "$IMAGE" 2>/dev/null)
$DOCKER_CMD pull $IMAGE
NEW_IMAGE_ID=$($DOCKER_CMD images --format "{{.ID}}" "$IMAGE" 2>/dev/null)

if [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ] && [ -n "$OLD_IMAGE_ID" ]; then
    echo "  Image is up to date."
else
    echo "  New image downloaded!"
fi
echo ""

# ----- Step 2: Check existing container -----
EXISTING=$($DOCKER_CMD ps -a --filter "name=^/${CONTAINER}$" --format "{{.Status}}" 2>/dev/null)

if [ -n "$EXISTING" ]; then
    RUNNING_IMAGE_ID=$($DOCKER_CMD inspect "$CONTAINER" --format "{{.Image}}" 2>/dev/null | cut -c8-19)
    LATEST_SHORT=$(echo "$NEW_IMAGE_ID" | cut -c1-12)

    if echo "$EXISTING" | grep -q "Up"; then
        echo "Container '$CONTAINER' is currently running."
        echo "  Status:        $EXISTING"

        if [ "$RUNNING_IMAGE_ID" != "$LATEST_SHORT" ]; then
            echo "  Image:         outdated (update available)"
            echo ""
            read -p "Update to new image and restart? [Y/n]: " REPLACE
        else
            echo "  Image:         up to date"
            echo ""
            read -p "Restart anyway? [Y/n]: " REPLACE
        fi
        REPLACE="${REPLACE:-Y}"
    else
        echo "Container '$CONTAINER' exists but is stopped."
        echo "  Status: $EXISTING"
        echo ""
        read -p "Remove and start fresh? [Y/n]: " REPLACE
        REPLACE="${REPLACE:-Y}"
    fi

    if [[ "$REPLACE" =~ ^[Yy]$ ]]; then
        echo ""
        echo "Removing old container..."
        $DOCKER_CMD stop $CONTAINER 2>/dev/null || true
        $DOCKER_CMD rm $CONTAINER 2>/dev/null || true
        echo ""
    else
        echo ""
        echo "No changes made. Container '$CONTAINER' is still running."
        echo ""
        echo "To update later, run this script again:"
        echo "  bash $0"
        echo ""
        exit 0
    fi
fi

# ----- Step 3: Ensure host-cache is writable by the sandbox (idempotent) -----
# The nsjail'd ClientApp installs each FAB to <host-cache>/flwr/apps/<name>.<hash>/
# as root (the container runs --user 0:0 and nsjail maps 0->0). If apps/ (or
# runtime-envs/) is owned by UID 1000 — e.g. left over from a pre-fix install —
# the install fails with PermissionError and every round returns 0 results
# (no weights, no metrics). Re-assert root ownership on every start so a stale
# 1000-owned subdir self-heals.
HOST_CACHE_DIR="__HOST_CACHE_DIR__"
# chown the host dir directly (not via docker). On Linux the setup used sudo for
# docker, so mirror that here; on macOS/WSL the mount layer maps UID and this is
# a no-op that harmlessly fails.
SUDO=""
if [ "$DOCKER_CMD" != "docker" ]; then SUDO="sudo"; fi
if [ -d "$HOST_CACHE_DIR" ]; then
    $SUDO mkdir -p "$HOST_CACHE_DIR/flwr/apps" "$HOST_CACHE_DIR/flwr/runtime-envs" "$HOST_CACHE_DIR/cache" 2>/dev/null || true
    # Root ownership to match the root container (nsjail maps root 0->0); a
    # 1000-owned dir here is unwritable by the sandbox and breaks every round.
    $SUDO chown -R 0:0 "$HOST_CACHE_DIR" 2>/dev/null \
        || echo "  WARNING: could not chown $HOST_CACHE_DIR — FAB installs inside the sandbox may fail with PermissionError."
fi

# ----- Step 4: Start new container -----
echo "Starting client..."
__RUN_CMD__

echo ""
sleep 3

if $DOCKER_CMD ps | grep -q $CONTAINER; then
    echo "============================================"
    echo "  Client is running!"
    echo "============================================"
    echo ""
    echo "  Dashboard:  http://localhost:8501"
    echo ""
    echo "  Next steps:"
    echo "    1. Open the dashboard in your browser"
    echo "    2. Go to Node Configuration → Dataset Management"
    echo "    3. Enter a dataset name and click Add"
    echo "    4. Copy your data files into the folder it creates"
    echo ""
    echo "  Commands:"
    echo "    $DOCKER_CMD logs -f $CONTAINER      # Live logs"
    echo "    $DOCKER_CMD restart $CONTAINER       # Restart"
    echo "    bash $0                              # Update to latest"
    echo ""
else
    echo "  Container may have failed to start."
    echo "  Check logs: $DOCKER_CMD logs $CONTAINER"
    echo ""
fi
RUNEOF

sed -i "s|__DOCKER_CMD__|${DOCKER_CMD}|g" "$SAVE_DIR/run-client.sh"
sed -i "s|__HOST_CACHE_DIR__|${HOST_CACHE_DIR}|g" "$SAVE_DIR/run-client.sh"
sed -i "s|__RUN_CMD__|${RUN_CMD}|g" "$SAVE_DIR/run-client.sh"
chmod +x "$SAVE_DIR/run-client.sh"
echo "  Run command saved to: $SAVE_DIR/run-client.sh"

echo ""
echo "============================================"
echo "  Setup Complete"
echo "============================================"
echo ""

# -------------------------------------------------------
# Pull image and start
# -------------------------------------------------------

read -p "Pull the latest image and start the client now? [Y/n]: " START_NOW
START_NOW="${START_NOW:-Y}"

if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
    echo ""
    bash "$SAVE_DIR/run-client.sh"
else
    echo "To start the client later, run:"
    echo ""
    echo "  bash $SAVE_DIR/run-client.sh"
    echo ""
fi