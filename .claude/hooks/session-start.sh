#!/bin/bash
set -euo pipefail

# Only run in remote (Claude Code on the web) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

ANDROID_SDK_DIR="/opt/android-sdk"
CMDLINE_TOOLS_VERSION="11076708"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"

# Install Android SDK if not already present
if [ ! -d "${ANDROID_SDK_DIR}/cmdline-tools/latest" ]; then
  echo "Installing Android SDK command-line tools..."
  mkdir -p "${ANDROID_SDK_DIR}/cmdline-tools"
  cd /tmp
  curl -fsSL -o cmdline-tools.zip "${CMDLINE_TOOLS_URL}"
  unzip -q -o cmdline-tools.zip
  rm -f cmdline-tools.zip
  mv cmdline-tools "${ANDROID_SDK_DIR}/cmdline-tools/latest"
fi

# Set environment variables for this session
echo "export ANDROID_HOME=${ANDROID_SDK_DIR}" >> "$CLAUDE_ENV_FILE"
echo "export ANDROID_SDK_ROOT=${ANDROID_SDK_DIR}" >> "$CLAUDE_ENV_FILE"
echo 'export PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"' >> "$CLAUDE_ENV_FILE"

# Export for use in this script
export ANDROID_HOME="${ANDROID_SDK_DIR}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_DIR}"
export PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

# Accept licenses non-interactively
yes | sdkmanager --licenses > /dev/null 2>&1 || true

# Install required SDK components if not already installed
if [ ! -d "${ANDROID_SDK_DIR}/platforms/android-34" ]; then
  echo "Installing Android SDK platform 34..."
  sdkmanager "platforms;android-34"
fi

if [ ! -d "${ANDROID_SDK_DIR}/build-tools/34.0.0" ]; then
  echo "Installing Android build-tools 34.0.0..."
  sdkmanager "build-tools;34.0.0"
fi

if [ ! -d "${ANDROID_SDK_DIR}/platform-tools" ]; then
  echo "Installing Android platform-tools..."
  sdkmanager "platform-tools"
fi

echo "Android SDK setup complete."
