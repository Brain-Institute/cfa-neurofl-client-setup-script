#!/bin/bash
# =============================================================
# NeuroFL Client Node Setup
# =============================================================
# One script for all platforms. Run once per machine.
#
# Linux:     curl -sSL https://raw.githubusercontent.com/Brain-Institute/cfa-neurofl-client-setup-script/main/setup-client.sh -o setup-client.sh && sudo bash setup-client.sh
# Mac:       curl -sSL https://raw.githubusercontent.com/Brain-Institute/cfa-neurofl-client-setup-script/main/setup-client.sh -o setup-client.sh && bash setup-client.sh
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
# Collect inputs
# -------------------------------------------------------

read -p "Enter your API Token: " API_TOKEN
if [ -z "$API_TOKEN" ]; then
    echo "Error: API Token is required."
    exit 1
fi

read -p "Enter your VM/Node Name (e.g., holland-bloorview-node-1): " VM_NAME
if [ -z "$VM_NAME" ]; then
    echo "Error: VM Name is required."
    exit 1
fi

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

DEFAULT_SERVER="https://api.neurofl.ca"
read -p "Server URL [$DEFAULT_SERVER]: " SERVER_URL
SERVER_URL="${SERVER_URL:-$DEFAULT_SERVER}"

echo ""
echo "--------------------------------------------"
echo "  Configuration"
echo "--------------------------------------------"
echo "  API Token:    ${API_TOKEN:0:8}..."
echo "  VM Name:      $VM_NAME"
echo "  Data Dir:     $DATA_DIR"
echo "  Logs Dir:     $LOGS_DIR"
echo "  Server:       $SERVER_URL"
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
# Linux-specific: seccomp + ACLs
# -------------------------------------------------------

SECCOMP_FLAG=""

if [ "$OS" = "Linux" ] && [ "$IS_WSL" = false ]; then
    CONFIG_DIR="/opt/fl-client"
    mkdir -p "$CONFIG_DIR"

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
            "comment": "Required for bubblewrap (bwrap) sandbox inside the container"
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
    echo "  Seccomp profile installed"

    if ! command -v setfacl &> /dev/null; then
        apt-get update -qq && apt-get install -y -qq acl > /dev/null 2>&1
        echo "  ACL support installed"
    fi

    setfacl -R -m u:1000:rwx "$DATA_DIR"
    setfacl -R -d -m u:1000:rwx "$DATA_DIR"
    setfacl -R -m u:1000:rwx "$LOGS_DIR"
    setfacl -R -d -m u:1000:rwx "$LOGS_DIR"
    echo "  Container permissions set"

    SECCOMP_FLAG="--cap-drop ALL --cap-add SYS_ADMIN --security-opt seccomp=$CONFIG_DIR/seccomp-profile.json"
fi

# -------------------------------------------------------
# Build the docker run command
# -------------------------------------------------------

DOCKER_CMD="docker"
if [ "$OS" = "Linux" ] && [ "$IS_WSL" = false ]; then
    DOCKER_CMD="sudo docker"
fi

RUN_CMD="$DOCKER_CMD run -d --name fl-client \
  --restart unless-stopped \
  ${SECCOMP_FLAG:+$SECCOMP_FLAG} \
  -p 8501:8501 \
  -v ${DATA_DIR}:/data \
  -v ${LOGS_DIR}:/app/logs \
  -e FL_SERVER_URL=\"${SERVER_URL}\" \
  -e API_TOKEN=\"${API_TOKEN}\" \
  -e VM_NAME=\"${VM_NAME}\" \
  daccacrneurofed.azurecr.io/fl-client:latest"

RUN_CMD=$(echo "$RUN_CMD" | sed 's/  */ /g')

# -------------------------------------------------------
# Save run-client.sh (handles updates, pulls, restarts)
# -------------------------------------------------------

SAVE_DIR="/opt/fl-client"
if [ "$OS" != "Linux" ] || [ "$IS_WSL" = true ]; then
    SAVE_DIR="$HOME/.neurofl"
fi
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

echo ""
echo "=== NeuroFL Client ==="
echo ""

# ----- Step 1: Pull latest image -----
echo "Checking for updates..."
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
    # Get the image ID the running container was built from
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

# Replace placeholders with actual values
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