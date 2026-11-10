#!/bin/zsh
# One-time setup: generates both Xcode projects, installs the CLI, points the app at the Runner.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null; then
  echo "xcodegen not found. Installing with Homebrew…"
  brew install xcodegen
fi

echo "▸ Generating Runner project"
(cd Runner && xcodegen generate)

echo "▸ Generating TestBridge app project"
xcodegen generate

echo "▸ Building testbridge CLI"
swift build -c release --product testbridge
mkdir -p "$HOME/.local/bin"
cp .build/release/testbridge "$HOME/.local/bin/testbridge"

RUNNER="$(pwd)/Runner/TestBridgeRunner.xcodeproj"
defaults write com.leeo.testbridge.TestBridge runnerProjectPath -string "$RUNNER"

cat <<MSG

Done.
  • open TestBridge.xcodeproj and run the TestBridge scheme
  • CLI installed at ~/.local/bin/testbridge  (add to PATH if needed)
  • export TESTBRIDGE_RUNNER_PROJECT="$RUNNER"   # for the CLI
  • testbridge doctor
MSG
