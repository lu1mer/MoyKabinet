#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
DOTNET_BIN="${DOTNET_BIN:-/Users/ilnursalahov/.dotnet/dotnet}"

if [[ ! -x "$DOTNET_BIN" ]]; then
  print -u2 "Dotnet executable not found: $DOTNET_BIN"
  print -u2 "Install .NET 10 SDK or set DOTNET_BIN=/absolute/path/to/dotnet"
  exit 1
fi

export ASPNETCORE_ENVIRONMENT=Development
export ASPNETCORE_URLS='http://127.0.0.1:8787'
cd "$SCRIPT_DIR"
exec "$DOTNET_BIN" run --no-launch-profile --project src/MoyKabinet.Api
