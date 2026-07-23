#!/bin/bash
echo "🚀 Deploying SigNoz..."
cd "$(dirname "$0")/.."
foundryctl cast -f casting.yaml
echo "✅ SigNoz deployed at http://localhost:8080"
