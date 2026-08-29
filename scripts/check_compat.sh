#!/usr/bin/env bash
# scripts/check_compat.sh
set -euo pipefail

PLUGIN_DIR="${1:-keybind-cheatsheet}"

if [ ! -d "$PLUGIN_DIR" ]; then
    echo "[ERROR] Plugin directory not found at $PLUGIN_DIR"
    exit 1
fi

# Dynamically find any TOML configuration file in the plugin root directory
CONFIG_FILE=""
for candidate in "$PLUGIN_DIR/manifest.toml" "$PLUGIN_DIR/plugin.toml" "$PLUGIN_DIR"/*.toml; do
    if [ -f "$candidate" ]; then
        CONFIG_FILE="$candidate"
        break
    fi
done

if [ -z "$CONFIG_FILE" ]; then
    echo "[ERROR] No configuration TOML file found in $PLUGIN_DIR"
    exit 1
fi

echo "[INFO] Using configuration file: $CONFIG_FILE"

DECLARED_API=$(grep -E '^[[:space:]]*plugin_api[[:space:]]*=' "$CONFIG_FILE" | grep -oE '[0-9]+' || true)

if [ -z "$DECLARED_API" ]; then
    echo "[ERROR] 'plugin_api' not found in $CONFIG_FILE"
    exit 1
fi

echo "[INFO] Inspecting [$PLUGIN_DIR] (Target Plugin API: $DECLARED_API)..."
VIOLATIONS=0

check_rule() {
    local feat="$1"
    local min_api="$2"
    local pattern="$3"

    if [ "$DECLARED_API" -lt "$min_api" ]; then
        if grep -Eq "$pattern" "$CONFIG_FILE" 2>/dev/null || grep -Erq "$pattern" "$PLUGIN_DIR"/*.luau 2>/dev/null; then
            echo "  [FAIL] Feature '$feat' requires plugin_api >= $min_api (declared: $DECLARED_API)"
            VIOLATIONS=$((VIOLATIONS + 1))
        fi
    fi
}

check_rule "string_map config types" 6 'type[[:space:]]*=[[:space:]]*"string_map"'
check_rule "widget.actions table" 14 '\[widget\.actions\]'
check_rule "noctalia.state.watch()" 8 'noctalia\.state\.watch'
check_rule "drag-and-drop UI nodes" 5 'ui\.dropTarget'
check_rule "key chords capture_keys" 12 'capture_keys'
check_rule "launcher prefix-relative queries" 9 'launcher\.setQuery'

if [ "$VIOLATIONS" -eq 0 ]; then
    echo "[PASS] Compatibility check passed. No undeclared API capabilities detected."
else
    echo ""
    echo "[FAIL] Found $VIOLATIONS API compatibility violation(s)."
    exit 1
fi
