#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
abt_test_dir=$(mktemp -d "${TMPDIR:-/tmp}/askbeforecallingtoo26.XXXXXX")
trap 'rm -rf "$abt_test_dir"' EXIT HUP INT TERM
xcrun --sdk macosx clang -g -fobjc-arc -fblocks -fstack-protector-strong \
 -fsanitize=address,undefined -Wall -Wextra -Wno-unused-parameter \
 -framework Foundation Settings/ABC26Model.m Settings/ABC26Store.m tests/settings.m -o "$abt_test_dir/settings"
"$abt_test_dir/settings" "$PWD/Settings/Resources/ABC26Schema.plist" "$abt_test_dir"
xcrun --sdk macosx clang -g -fobjc-arc -fblocks -fstack-protector-strong \
 -fsanitize=address,undefined -Wall -Wextra -Wno-unused-parameter -Wno-unused-function \
 -Wno-deprecated-declarations -Itests -ISettings -framework Foundation -framework CoreFoundation \
 Engine/ABTCore.m Engine/ABTCallURL.m Settings/ABC26Model.m Settings/ABC26Store.m tests/runtime.m -o "$abt_test_dir/runtime"
"$abt_test_dir/runtime" "$abt_test_dir/runtime-files"
