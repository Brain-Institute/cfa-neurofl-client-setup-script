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

BUNDLE_PATH="$1"
if [ -z "$BUNDLE_PATH" ] || [ ! -f "$BUNDLE_PATH" ]; then
    echo "Usage: bash setup-client.sh <site>-onboarding.tar.gz"
    echo "Error: onboarding bundle not found."
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
tar -xzf "$BUNDLE_PATH" -C "$WORK"

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
# (several GB) which would overflow the packaged 1 GB tmpfs. Owned by UID 1000 so
# the sandboxed ClientApp (fluser) can write extracted wheels here.
HOST_CACHE_DIR="/var/lib/flwr-cache/${VM_NAME}"
mkdir -p "$HOST_CACHE_DIR/cache" "$HOST_CACHE_DIR/flwr"
chown -R 1000:1000 "$HOST_CACHE_DIR" 2>/dev/null || true
echo "  Host-backed dependency cache ready at $HOST_CACHE_DIR"

# nsjail needs SYS_ADMIN + the seccomp profile on EVERY platform (bwrap could
# run rootless; this nsjail setup cannot). SETUID/SETGID let gosu drop to the
# container's UID 1000.
SECURITY_FLAGS="--cap-drop ALL --cap-add SYS_ADMIN --cap-add SETUID --cap-add SETGID --security-opt seccomp=$CONFIG_DIR/seccomp-profile.json"

# Linux-only host extras: AppArmor override (docker-default would block nsjail's
# mounts) and POSIX ACLs so the UID-1000 container can write to data/logs.
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
  -e FLWR_SUPEREXEC_SANDBOX_CONFIG=/etc/neurofl/nsjail.cfg \
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

# ----- Step 3: Start new container -----
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
