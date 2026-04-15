#!/usr/bin/env bats

setup() {
  ORIGINAL_PATH="$PATH"
  TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/uvenv-test.XXXXXX")"
  PROJECT_DIR="$TEST_ROOT/project"
  MOCK_BIN="$TEST_ROOT/mock-bin"
  UV_SCRIPT_PATH="$BATS_TEST_DIRNAME/../bin/uvenv.sh"
  SAMPLE_APP_DIR="$BATS_TEST_DIRNAME/sample_app"

  mkdir -p "$PROJECT_DIR" "$MOCK_BIN"

  cat > "$MOCK_BIN/python3" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$MOCK_BIN/python3"

  cat > "$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
echo TestOS
EOF
  chmod +x "$MOCK_BIN/uname"

  export PATH="$MOCK_BIN:$PATH"

  mkdir -p "$PROJECT_DIR/.venv/TestOS/bin"
  cat > "$PROJECT_DIR/.venv/TestOS/bin/activate" <<EOF
VIRTUAL_ENV="$PROJECT_DIR/.venv/TestOS"
export VIRTUAL_ENV
EOF
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "fails when uv is not available" {
  export PATH="$MOCK_BIN:/usr/bin:/bin"

  run sh -c 'cd "$1" && . "$2"' _ "$PROJECT_DIR" "$UV_SCRIPT_PATH"

  [ "$status" -ne 0 ]
  [[ "$output" == *"uv not found"* ]]
}

@test "creates and uses uvenv for sample app dependencies" {
  APP_WORKDIR="$TEST_ROOT/sample-app-uv"
  UV_BIN="$TEST_ROOT/uv-bin"
  mkdir -p "$APP_WORKDIR" "$UV_BIN"
  cp -R "$SAMPLE_APP_DIR/." "$APP_WORKDIR"

  cat > "$UV_BIN/uv" <<'EOF'
#!/usr/bin/env sh
if [ "$1" = "pip" ]; then
  shift
  python -m pip "$@"
else
  echo "unsupported uv command" >&2
  exit 1
fi
EOF
  chmod +x "$UV_BIN/uv"

  export PATH="$UV_BIN:$ORIGINAL_PATH"

  run sh -c 'cd "$1" && . "$2" && python app.py' _ "$APP_WORKDIR" "$UV_SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [[ "$output" == *"imports-ok"* ]]
}
