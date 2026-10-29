#!/bin/sh
set -eu
cd "$(dirname "$0")"
: "${THEOS:?Set THEOS to the RootHide Theos checkout}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build-cache/modules"
mkdir -p validation
sh tests/run.sh > validation/tests.log 2>&1
cat validation/tests.log
make clean package
python3 normalize_package.py packages/com.sahinkaa.askbeforecallingtoo26_1.0_iphoneos-arm64e.deb
python3 validate_package.py packages/com.sahinkaa.askbeforecallingtoo26_1.0_iphoneos-arm64e.deb > validation/package.json
