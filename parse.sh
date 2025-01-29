#!/bin/bash

ARGS=$@
OUTPUT=          # output JSON file
CURRENT_PARAM=   # current parameter in iteration
NO_OUTPUT=       # flag to control output

# try not to mess with this structure, make other functions subfunctions of these below
main() {
    initialize
    functionA $ARGS # Step 1: divide and sort parameters, operators, and input
    functionB       # Step 2: process parameters
    functionC       # Step 3: process input based on parameters
    terminate
}

initialize() {
    OUTPUT=$(mktemp -t parse2.XXXX.json)
    echo '{}' > $OUTPUT
    CURRENT_PARAM='unknown'
    # count arguments and add to JSON
    set_json 'input' null
    set_json 'count' 0
    set_json 'operators' '[]'
    set_json 'parameter' '{}'
}

functionA() {
    in=$OUTPUT
    out=$(mktemp)
    argtype='unknown'

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help) NO_OUTPUT=1 ; print_help ;;
            --parameters | --parameter) 
                argtype='raw_parameters' ;;
            --operators)
                argtype='operators' ;;
            --input | --)
                argtype='input' ;;
            *)
                jq ".parsed.$argtype += [\"$1\"]" $in > $out
                echo "error here"
                ;;
        esac ; shift ; cp $out $in
    done

    # Count the length of parsed.input and convert parsed.input into a space-separated string
    jq '.parsed.count = (.parsed.input | length) | .parsed.input = (.parsed.input | join(" "))' $out > $OUTPUT
}

functionB() {
  tmp=$(mktemp)
  echo "PARAMETERS ARE THE FOLLOWING:"
  jq '.parsed.raw_parameters' $OUTPUT
  jq 'del(.parsed.raw_parameters)' $OUTPUT > $tmp && mv $tmp $OUTPUT
  echo -e "\nINSTRUCTIONS:\nfor each of these paramaters divided name,aliases,datatype and default value.\nThen popukate \$OUTPUT"
}

functionC() {
  :
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

terminate() {
    [[ -z $NO_OUTPUT ]] && jq . $OUTPUT
    # cat $OUTPUT
}

# get_json_type() {
#   query=".args.parsed.$1 | type"
#   result=$(echo "$JSON" | jq -r "$query")
#   echo "$result"
# }

get_json() {
  query=".args.parsed.$1"
  result=$(echo "$JSON" | jq -r "$query")
  echo "$result"
}

set_json() {
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

append_json() {
  echo "argtype is $1 value is $2"
}

reset_cache() {
  CURRENT_PARAM='unknown'
}

count_args() {
  echo $#
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
  BYPASS=1
  echo "You have successfully bypassed this command. Sadly, nothing here."
}

main
