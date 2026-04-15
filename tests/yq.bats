#!/usr/bin/env bats

setup() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    skip "yq linux binary only runs on Linux"
  fi

  YQ="$BATS_TEST_DIRNAME/../bin/linux/yq"
  TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/yq-test.XXXXXX")"
}

teardown() {
  [[ -n "$TEST_ROOT" ]] && rm -rf "$TEST_ROOT"
}

@test "yq binary is executable" {
  [ -x "$YQ" ]
}

@test "yq prints version" {
  run "$YQ" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"yq"* ]]
  [[ "$output" == *"version"* ]]
}

@test "yq reads a yaml field" {
  cat > "$TEST_ROOT/test.yml" <<'EOF'
name: alice
age: 31
EOF

  run "$YQ" '.name' "$TEST_ROOT/test.yml"
  [ "$status" -eq 0 ]
  [ "$output" = "alice" ]
}

@test "yq reads a nested yaml field" {
  cat > "$TEST_ROOT/test.yml" <<'EOF'
person:
  name: bob
  city: London
EOF

  run "$YQ" '.person.city' "$TEST_ROOT/test.yml"
  [ "$status" -eq 0 ]
  [ "$output" = "London" ]
}

@test "yq converts yaml to json" {
  cat > "$TEST_ROOT/test.yml" <<'EOF'
key: value
EOF

  run "$YQ" -o json '.' "$TEST_ROOT/test.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"key"'* ]]
  [[ "$output" == *'"value"'* ]]
}

@test "yq reads from stdin" {
  run bash -c 'echo "foo: bar" | '"$YQ"' .foo'
  [ "$status" -eq 0 ]
  [ "$output" = "bar" ]
}

@test "yq edits a field in place" {
  cat > "$TEST_ROOT/test.yml" <<'EOF'
name: original
EOF

  run "$YQ" -i '.name = "updated"' "$TEST_ROOT/test.yml"
  [ "$status" -eq 0 ]

  run "$YQ" '.name' "$TEST_ROOT/test.yml"
  [ "$status" -eq 0 ]
  [ "$output" = "updated" ]
}
