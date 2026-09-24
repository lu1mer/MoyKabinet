#!/bin/zsh
set -e
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$DOTNET_ROOT:$PATH"
PROJECT_ROOT="${0:A:h}"
cd "$PROJECT_ROOT/Server.AspNetCore"
exec dotnet run --project src/MoyKabinet.Api
