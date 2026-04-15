#!/usr/bin/env bats

setup() {
  ORIGINAL_PATH="$PATH"
  TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/venv-test.XXXXXX")"
  PROJECT_DIR="$TEST_ROOT/project"
  MOCK_BIN="$TEST_ROOT/mock-bin"
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../bin/venv.sh"
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

@test "activates existing uname-based venv and defines workdir alias" {
  run bash -c 'cd "$1" && source "$2" && alias workdir && printf "\n%s" "$VIRTUAL_ENV"' _ "$PROJECT_DIR" "$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [[ "$output" == *"workdir='cd $PROJECT_DIR'"* ]]
  [[ "$output" == *"$PROJECT_DIR/.venv/TestOS" ]]
}

@test "uses WSL_DISTRO_NAME when set" {
  mkdir -p "$PROJECT_DIR/.venv/MyWSL/bin"
  cat > "$PROJECT_DIR/.venv/MyWSL/bin/activate" <<EOF
VIRTUAL_ENV="$PROJECT_DIR/.venv/MyWSL"
export VIRTUAL_ENV
EOF

  run bash -c 'cd "$1" && export WSL_DISTRO_NAME=MyWSL && source "$2" && printf "%s" "$VIRTUAL_ENV"' _ "$PROJECT_DIR" "$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ "$output" = "$PROJECT_DIR/.venv/MyWSL" ]
}

@test "runs successfully with sh when executed directly" {
  run sh -c 'cd "$1" && sh "$2"' _ "$PROJECT_DIR" "$SCRIPT_PATH"

  [ "$status" -eq 0 ]
}

@test "creates and uses venv for sample app dependencies" {
  APP_WORKDIR="$TEST_ROOT/sample-app"
  mkdir -p "$APP_WORKDIR"
  cp -R "$SAMPLE_APP_DIR/." "$APP_WORKDIR"

  export PATH="$ORIGINAL_PATH"

  run sh -c 'cd "$1" && . "$2" && python app.py' _ "$APP_WORKDIR" "$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [[ "$output" == *"imports-ok"* ]]
}
