#!/usr/bin/env bats

setup() {
  TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/csv2json-test.XXXXXX")"
  WORKDIR="$TEST_ROOT/work"
  MOCK_BIN="$TEST_ROOT/mock-bin"
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../bin/csv2json"

  mkdir -p "$WORKDIR" "$MOCK_BIN"

  cat > "$MOCK_BIN/mlr" <<'EOF'
#!/usr/bin/env sh
cat <<JSON
[{"name":"alice","age":"31"}]
JSON
EOF
  chmod +x "$MOCK_BIN/mlr"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "prints usage and exits non-zero with no args" {
  run bash "$SCRIPT_PATH"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "converts csv to json file" {
  cat > "$WORKDIR/people.csv" <<'EOF'
name,age
alice,31
EOF

  run env PATH="$MOCK_BIN:$PATH" bash -c 'cd "$1" && bash "$2" people.csv' _ "$WORKDIR" "$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [[ "$output" == *"people.csv > people.json"* ]]
  [ -f "$WORKDIR/people.json" ]

  run cat "$WORKDIR/people.json"
  [ "$status" -eq 0 ]
  [ "$output" = '[{"name":"alice","age":"31"}]' ]
}
