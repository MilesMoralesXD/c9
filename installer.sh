#!/usr/bin/env bash
set -e

function usage() {
  cat <<EOF
Usage: $0 -p <password>

Options:
  -p PASSWORD   Password for the Cloud9 root user (required)
  -h            Show this help message and exit
EOF
  exit 1
}

# Parse command-line arguments
typeset PASSWORD=""
while getopts ":p:h" opt; do
  case $opt in
    p) PASSWORD="$OPTARG" ;;  # Cloud9 root password
    h|\?) usage ;;
  esac
done

# Ensure password was provided
if [[ -z "$PASSWORD" ]]; then
  echo "Error: Password is required."
  usage
fi

echo "==========================================="
echo "   Medusa Cloud9 installer"
echo "==========================================="

# Ensure we're root (or running under sudo)
if (( EUID != 0 )); then
  echo "Please run as root (or via sudo)."
  exit 1
fi

# 1) Detect architecture
arch=$(uname -m)
echo "Detected architecture: $arch"

# 2) Install Docker
if ! command -v docker >/dev/null; then
  if [[ $arch == arm* || $arch == aarch64 ]]; then
    echo "Installing Docker via snap..."
    snap install docker
  else
    echo "Installing Docker via apt..."
    apt-get update
    apt-get install -y docker.io
  fi
else
  echo "✔ Docker is already installed."
fi

# 3) Install docker-compose if missing
if ! command -v docker-compose >/dev/null; then
  echo "Installing docker-compose via apt..."
  apt-get update
  apt-get install -y docker-compose
else
  echo "✔ docker-compose is already installed."
fi

# 4) Determine user home + UID/GID
#    (if run with sudo, use the invoking user)
user=$(whoami)
home_dir=$(eval echo "~$user")
PUID=$(id -u "$user")
PGID=$(id -g "$user")

echo "Container will run as UID:$PUID GID:$PGID (user: $user)"

# 5) Create workspace dirs
mkdir -p "$home_dir/cloud9/code"
chown -R "$PUID:$PGID" "$home_dir/cloud9"

# 6) Generate docker-compose.yml
cat > "$home_dir/cloud9/docker-compose.yml" <<EOF
version: "2.1"
services:
  cloud9:
    image: lscr.io/linuxserver/cloud9:latest
    container_name: cloud9
    environment:
      - PUID=$PUID
      - PGID=$PGID
      - TZ=Europe/London
      - USERNAME=root
      - PASSWORD=$PASSWORD
    volumes:
      - $home_dir/cloud9/code:/code
      - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - 8000:8000
    restart: unless-stopped
EOF

echo "Generated docker-compose.yml in $home_dir/cloud9"

# 7) Launch
cd "$home_dir/cloud9"
docker-compose up -d

echo
echo "🎉 Cloud9 is now running!"
echo "   Point your browser at: http://$(hostname -I | awk '{print $1}'):8000"
echo "   Login with USERNAME=root and your password."