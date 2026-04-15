#!/bin/sh

venv_fail() {
  return 1
}

if command -v python3 >/dev/null 2>&1
then
  pcommand=$( command -v python3)
else
  if command -v python >/dev/null 2>&1
  then
    pcommand=$( command -v python)
  else
    echo "Python must be installed."
    echo "  -> python3 or python command not found."
    venv_fail || return 1 2>/dev/null || exit 1
  fi
fi

if ! "$pcommand" -c 'import venv' >/dev/null 2>&1
then
  echo venv python package not found. Please install venv package
  venv_fail || return 1 2>/dev/null || exit 1
fi

if ! command -v uv >/dev/null 2>&1
then
  echo uv not found. Please install uv and try again
  venv_fail || return 1 2>/dev/null || exit 1
fi

if [ -z "$WSL_DISTRO_NAME" ]
then
  distname=$(uname)
else
  distname=$WSL_DISTRO_NAME
fi

if ! [ -d ".venv/$distname" ]
then
  echo Creating Virtual Environment: ".venv/$distname"
  "$pcommand" -m venv .venv/$distname
  venv_install_reqs="yes"
else
  unset venv_install_reqs
fi

. .venv/$distname/bin/activate
alias workdir="cd $(pwd)"

if [ -n "$venv_install_reqs" ]
then
  uv pip install --upgrade pip
  if [ -e "requirements.txt" ]
  then
    while IFS="" read -r p || [ -n "$p" ]
    do
      if ! python -c "import $p" >/dev/null 2>&1
      then
        uv pip install "$p"
      fi
    done < requirements.txt
  fi
fi

unset venv_install_reqs

# send