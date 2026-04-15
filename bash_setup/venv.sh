#!/bin/bash
if command -v python3 &> /dev/null
then
  pcommand=$( command -v python3)
else
  if command -v python &> /dev/null
  then
    pcommand=$( command -v python)
  else
    echo "Python must be installed."
    echo "  -> python3 or python command not found."
    return
  fi
fi

# echo $($pcommand --version) found: $pcommand

if ! command $pcommand -c 'import pip' &> /dev/null
then
  echo pip not found. Please install pip
  return
fi

if ! command $pcommand -c 'import venv' &> /dev/null
then
  echo venv python package not found. Please install venv package
  return
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
  $pcommand -m venv .venv/$distname
  venv_install_reqs="yes"
else
  unset venv_install_reqs
fi

source .venv/$distname/bin/activate

if [ -n "$venv_install_reqs" ]
then
  pip install --upgrade pip
  if [ -e "requirements.txt" ]
  then
    while IFS="" read -r p || [ -n "$p" ]
    do
      if ! command python -c "import $p" &> /dev/null
      then
        python -m pip install $p
      fi
    done < requirements.txt
  fi
fi

unset venv_install_reqs

# send
