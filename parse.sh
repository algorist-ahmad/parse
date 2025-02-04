#!/bin/bash

ARGS=$@
ARGS_UNKNOWN=    # args without paramater
OUTPUT=          # output JSON file
# CURRENT_PARAM=   # current parameter in iteration
NO_OUTPUT=       # flag to control output

# try not to mess with this structure, make other functions subfunctions of these below
main() {
    initialize
    functionA $ARGS # Step 1: divide and sort parameters, operators, and input
    functionB       # Step 2: process RAW parameters (separate by , then by : then by = then by /) name/alias:type=default,name2
    functionC       # Step 3: process input based on parameters
    terminate
}

initialize() {
    validate_args "$ARGS"
    # create output file
    OUTPUT=$(mktemp -t parse2.XXXX.json)
    echo '{}' > $OUTPUT
    # count arguments and add to JSON
    json_set 'input' null
    json_set 'count' 0
    json_set 'operators' '[]'
    json_set 'parameter' '{}'
}

functionA() {
    param='unknown'
    ignore=0         # tells case-esac to ignore this argument, do not json_add

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help) NO_OUTPUT=1 ; [[ "$param" == 'unknown' ]] && print_help ;;
            --parameters | --parameter) 
                [[ $param != 'input' ]] && ignore=1 && param='raw.parameters' ;;&
            --operators | --operator)
                [[ $param != 'input' ]] && ignore=1 && param='operators' ;;&
            --input | --args | --)
                [[ $param != 'input' ]] && ignore=1 && param='input' ;;&
            *)
                if [[ $param == 'unknown' ]]
                  then ARGS_UNKNOWN+=" $1,"
                elif [[ $ignore == 0 ]]
                  then json_add -a "$param" "$1"
                fi
                ;;
        esac ; shift ; ignore=0
    done
}

# processes parametersss
functionB() {
  tmp=$(mktemp)
  echo "PARAMETERS ARE THE FOLLOWING:"
  jq '.parsed.raw.parameters' $OUTPUT
  # jq 'del(.parsed.raw_parameters)' $OUTPUT > $tmp && mv $tmp $OUTPUT
  echo -e "\nINSTRUCTIONS:\nITERATE raw params and for each, split into aliases,datatype and default value.\nThen popukate \$OUTPUT"
}

# processes input
functionC() {
  # Count the length of parsed.input and convert parsed.input into a space-separated string
  input_string=$(jq -r '.parsed.input | join(" ")' $OUTPUT)
  input_count=$(jq '.parsed.input | length' $OUTPUT)
  json_set 'input' "$input_string"
  json_set 'count' $input_count

  # if no input received, capture interactively
  if [[ -z "$input_string" ]]; then
    input=$(cat)
    json_set 'input' '[]'
    for arg in $input
      do json_add -a 'input' "$arg"
    done
    functionC
  fi
}

dissect_old() {
    # if start with --, add as key, else add as value, but if literal '--', then set -- = true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            # --) add_special_key '--' ;;
            --help) NO_OUTPUT=1 ; print_help ;;
            --*) add_key "$1" ;;
            -*) add_key "-$1" ;;
            *) add_value "$CURRENT_OPT" "$1" ;;
        esac
        shift
    done
}

dissect() {
  echo 'dissecting...'
}

# terminates script with custom exit code
terminate() {
    [[ -z $NO_OUTPUT ]] && jq . $OUTPUT
    [[ -n "$ARGS_UNKNOWN" ]] && >&2 echo -e "\e[33mNO PARAMETER PROVIDED:$ARGS_UNKNOWN\b \e[0m"
    exit $1
}

# get_json_type() {
#   query=".$1 | type"
#   result=$(echo "$JSON" | jq -r "$query"
# }

json_get() {
  query=".$1"
  jq -r "$query" $OUTPUT
}

json_set() {
  local key="$1"
  local val=$(trim "$2")
  local tmp=$(mktemp)

  cp $OUTPUT $tmp

  # Determine the type of the value
  if [[ "$val" =~ ^[0-9]+$ ]]; then
    # Number
    jq ".parsed.$key = $val" $tmp > $OUTPUT
  elif [[ "$val" =~ ^\[(.*)\]$ ]]; then
    # Array (must be in JSON format)
    jq --argjson val "$val" ".parsed.$key = \$val" $tmp > $OUTPUT
  elif [[ "$val" =~ ^\{(.*)\}$ ]]; then
    # JSON Object (must be in JSON format)
    jq --argjson val "$val" ".parsed.$key = \$val" $tmp > $OUTPUT
  elif [[ "$val" == "true" || "$val" == "false" ]]; then
    # Boolean
    jq "parsed.$key = $val" $tmp > $OUTPUT
  elif [[ "$val" == "null" ]]; then
    # Null
    jq ".parsed.$key = null" $tmp > $OUTPUT
  else
    # String (default)
    jq ".parsed.$key = \"$val\"" $tmp > $OUTPUT
  fi
}

json_add() {
    tmp=$(mktemp)
    query=
    value=

    case "$1" in
      -a | --array)
        shift
        value="[\"$2\"]" ;;
      *)
        value="$2"
    esac

    query=".parsed.$1 += $value" # for array: "[\"$1\"]"
    cp $OUTPUT $tmp
    jq "$query" $tmp > $OUTPUT
}

add_key() {
    key= # the key to write to json file

    reset_cache
    
    # if key is literally --, set "--" to true
    if [[ "$1" == '--' ]]; then
      CURRENT_OPT='DOUBLEDASH'
    else
      CURRENT_OPT="${1:2}"
    fi

    edit_json "args.parsed.$CURRENT_OPT" true
}

add_value () {
  key="$1"
  new_value="$2"

  # if key is empty, replace with 'unknown'
  [[ -z "$key" ]] && key='unknown'

  # get json value, modify, and write
  old_value=$(get_json_value "$key")
  old_value_type=$(get_json_type "$key")

  # change datatype to (empty) string if boolean or null
  case "$old_value_type" in
    string) ;; # normal
    boolean | null) old_value= ;;
    *) >&2 echo "old_value_type is $old_value_type" ;;
  esac

  new_value=$(trim "$old_value $new_value")
  
  # echo "old value is $old_value, type is $old_value_type, new value is $new_value" #debug

  edit_json "args.parsed.$key" "$new_value"
}

# trim() {
#   echo "$*" | xargs --null
# }

trim() {
  echo "$*" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

print_help() {
  echo -e "HELP REQUESTED"
  echo -e "use --parameters, --operators, and --input"
  exit 0
}

validate_args() {
  if [[ -z "$@" ]]; then
    >&2 echo "No arg supplied!"
    sleep 2
    print_help
  fi
}

main
