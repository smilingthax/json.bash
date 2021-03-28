#!/bin/bash
# json_lib.sh shell library to parse json
# (c) 2021 Tobias Hoffmann

_jsonparse_maxnest=20  # NOTE: 0 disables

_jsonparse_read() {
#  IFS= read -r -s -N ${1:-1} ch
  IFS= read -r -s -d '' -n ${1:-1} ch
}

# reads from stdin (via _jsonparse_read)
_jsonparse() { # outfn [strict=0]
  local outfn=$1 maxnest=_jsonparse_maxnest ch

  if (( ${2:-0} != 0 )); then  # strict
#    while _jsonparse_read; do   # TODO? (allow empty input)
    while _jsonparse_read || return; do
      case "$ch" in
      [tfn\"0-9-]) return 3 ;;
      {) _jsonparse_object || return; break ;;
      [) _jsonparse_array || return; break ;;
      [$'\t\n\r ']) continue ;;  # whitespace
      *) return 2 ;;
      esac
    done
  else
#    _jsonparse_value "" 0 || return    # TODO? (allow empty input)
    _jsonparse_value || return
  fi

  while [[ $ch == [$'\t\n\r '] ]]; do
    _jsonparse_read || break
  done
  [[ $ch == "" ]] || return 2
}

_jsonparse_value() { # [allow_delim= [required=1]]
  while _jsonparse_read; do
    case "$ch" in
    t) _jsonparse_primitive t rue ;;
    f) _jsonparse_primitive f alse ;;
    n) _jsonparse_primitive n ull ;;
#    \") _jsonparse_string_raw ;;
    \") _jsonparse_string ;;
#    [-0-9]) _jsonparse_number_raw "$ch" ;;
    [-0-9]) _jsonparse_number "$ch" ;;
    {) _jsonparse_object ;;
    [) _jsonparse_array ;;
    [$'\t\n\r ']) continue ;;  # whitespace
    $1) return 0 ;;
    *) return 2 ;;
    esac
    return
  done
  return "${2:-$?}"
}

_jsonparse_key_outfn() {
#  key=$3          # TODO?
  "$outfn" k "${@:2}"
}

_jsonparse_key() { # {{{ [allow_delim=]
  while _jsonparse_read; do
    case "$ch" in
#    \") _jsonparse_string_raw _jsonparse_key_outfn || return ;;
    \") _jsonparse_string _jsonparse_key_outfn || return ;;
    $1) return 0 ;;
    [$'\t\n\r ']) continue ;;  # whitespace
    *) return 2 ;;
    esac

    while [[ $ch == [$'\t\n\r '] ]]; do
      _jsonparse_read || return
    done

    [[ $ch == : ]]
    return
  done
}
# }}}

_jsonparse_object() { # {{{
  (( --maxnest )) || return 4
  "$outfn" o "{"

  _jsonparse_key "}" || return
  if [[ $ch == : ]]; then
    while
      _jsonparse_value || return

      while [[ $ch == [$'\t\n\r '] ]]; do
        _jsonparse_read || return
      done
      [[ $ch == "," ]]
    do
      _jsonparse_key || return
    done
  fi

  [[ $ch == "}" ]] || return 2
  "$outfn" O "}"
  (( ++maxnest ))

  _jsonparse_read
  return 0
}
# }}}

_jsonparse_array() { # {{{
  (( --maxnest )) || return 4
  "$outfn" a "["

  _jsonparse_value "]" || return
  while
    while [[ $ch == [$'\t\n\r '] ]]; do
      _jsonparse_read || return
    done
    [[ $ch == "," ]]
  do
    _jsonparse_value || return
  done

  [[ $ch == "]" ]] || return 2
  "$outfn" A "]"
  (( ++maxnest ))

  _jsonparse_read
  return 0
}
# }}}

_jsonparse_primitive() { # {{{ ch0 expect
  _jsonparse_read ${#2} || return
  [[ $ch != $2 ]] && return 2
  "$outfn" "$1" "$1$2"

  _jsonparse_read
  return 0
}
# }}}

_jsonparse_number_raw() { # {{{ ch0
  local ret=$1
  while _jsonparse_read && [[ $ch == [0-9.eE+-] ]]; do
    ret+=$ch
  done
  "$outfn" 0 "$ret"
  return 0
}
# }}}

_jsonparse_number() { # {{{ ch0
  local sign int=$1 frac esign exp

  if [[ $1 == '-' ]]; then
    sign=$1
    _jsonparse_read || return
    int=$ch
  fi

  case "$int" in
  0) _jsonparse_read ;;
  [1-9])
    while _jsonparse_read && [[ $ch == [0-9] ]]; do
      int+=$ch
    done
    ;;
  *) return 2 ;;
  esac

  if [[ $ch == . ]]; then
    frac=$ch
    _jsonparse_read
    [[ $ch == [0-9] ]] || return 2
    frac+=$ch
    while _jsonparse_read && [[ $ch == [0-9] ]]; do
      frac+=$ch
    done
  fi

  if [[ $ch == [eE] ]]; then
    esign=$ch
    _jsonparse_read
    if [[ $ch == [+-] ]]; then
      esign+=$ch
      _jsonparse_read
    fi
    [[ $ch == [0-9] ]] || return 2
    exp+=$ch
    while _jsonparse_read && [[ $ch == [0-9] ]]; do
      exp+=$ch
    done
  fi

  if [[ ${#esign} -gt 0 ]]; then
    local esign1=${esign:1}
    "$outfn" 0 "$sign$int$frac$esign$exp" ${sign:-+} $int ${frac:1} ${esign1:-+} $exp
  else
    "$outfn" 0 "$sign$int$frac" ${sign:-+} $int ${frac:1}
  fi
  return 0
}
# }}}

_jsonparse_string() { # {{{ [outfn=$outfn]
  local ret tmp raw
  while _jsonparse_read; do
    case "$ch" in
    \")
      "${1:-$outfn}" s "\"$raw\"" "$ret"

      _jsonparse_read
      return 0
      ;;

    \\)
      _jsonparse_read
      case "$ch" in
      [bfnrt])
        raw+="\\$ch"
        printf -v tmp "%b" "\\$ch"
        ret+=$tmp
        ;;
      u)
        _jsonparse_read 4
        [[ $ch == [[:xdigit:]][[:xdigit:]][[:xdigit:]][[:xdigit:]] ]] || return 2
        raw+="\\u$ch"
        printf -v tmp "%b" "\\u$ch"
        ret+=$tmp
        ;;
      [\"\\/])
        raw+="\\$ch"
        ret+=$ch
        ;;
      *)
        return 2
#        raw+="\\$ch"
#        ret+=$ch  # TODO?
        ;;
      esac
      ;;

    $'\x7f') # in [:cntrl:], but allowed in json
      raw+=$ch
      ret+=$ch
      ;;

    [[:cntrl:]])     # FIXME... ensure LC_ALL=C
      return 2
      ;;

    *)
      raw+=$ch
      ret+=$ch
      ;;
    esac
  done
}
# }}}

_jsonparse_string_raw() { # {{{ [outfn=$outfn]
  local ret
  while _jsonparse_read; do
    case "$ch" in
    \")
      "${1:-$outfn}" s "\"$ret\""

      _jsonparse_read
      return 0
      ;;

    \\)
      _jsonparse_read
      case "$ch" in
      [bfnrt\"\\/]) ret+="\\$ch" ;;
      u)
        _jsonparse_read 4
        ret+="\\u$ch"
        ;;
#      *) ret+=$ch ;;   # TODO?
      *) return 2 ;;
      esac
      ;;

    $'\x7f') ret+=$ch ;; # in [:cntrl:], but allowed in json

    [[:cntrl:]]) return 2 ;;  # TODO?   # FIXME... ensure LC_ALL=C

    *) ret+=$ch ;;
    esac
  done
}
# }}}

# -- encode hlp --

_json_string_escape() {
  sed -e ':0' -e '$!{N' -e 'b0' -e '}' -e $'s/\\\\/\\\\\\\\/g; s/\\n/\\\\n/g; s/\t/\\\\t/g; s/\r/\\\\r/g; s/\f/\\\\f/g; s/\x08/\\\\b/g; s/"/\\\\"/g;  s/^.*$/"&"/'
}

