#!/usr/bin/env zsh

# Alias for the script
alias algolabVS='~/.algolabVS.sh'

# Completion function for algolabVS
_algolabVS_commands() {
  local -a commands
  commands=(
    'clean:Clean the project'
    'init:Initialize the project'
    'edit:Edit the project'
    'debug:Debug the project'
    'memcheck:Check memory usage'
    'run:Run the project'
    'compile:Compile the project'
    'test:Run tests'
    'version:Show version'
  )
  _describe 'command' commands
}

# Register the completion function
compdef _algolabVS_commands .algolabVS.sh
