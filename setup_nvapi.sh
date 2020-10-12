#!/bin/bash

nvapi_dir="$(dirname "$(readlink -fm "$0")")"
dll_ext='dll.so'
wine="wine"
lib='lib32'

if [ ! -f "$nvapi_dir/$lib/nvcuda.$dll_ext" ]; then
    echo "nvcuda.$dll_ext not found in $nvapi_dir/$lib" >&2
    exit 1
fi

winever=$($wine --version | grep wine)
if [ -z "$winever" ]; then
    echo "$wine:  Not a wine executable. Check your $wine." >&2
    exit 1
fi

quiet=false
assume=

function ask {
    echo "$1"
    if [ -z "$assume" ]; then
        read -r continue
    else
        continue=$assume
        echo "$continue"
    fi
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do

    case $1 in
    -y)
        assume='y'
        shift
        ;;
    -n)
        assume='n'
        shift
        ;;
    -q|--quiet)
        quiet=true
        assume=${assume:-'y'}
        shift 
        ;;
    *)
        POSITIONAL+=("$1")
        shift
        ;;
    esac
done
set -- "${POSITIONAL[@]}"

if [ "$quiet" = true ]; then
    exec >/dev/null
fi

if [ -z "$WINEPREFIX" ]; then
    ask "WINEPREFIX is not set, continue? (y/N)"
    if [ "$continue" != "y" ] && [ "$continue" != "Y" ]; then
    exit 1
    fi
else
    if ! [ -f "$WINEPREFIX/system.reg" ]; then
        ask "WINEPREFIX does not point to an existing wine installation. Proceeding will create a new one, continue? (y/N)"
        if [ "$continue" != "y" ] && [ "$continue" != "Y" ]; then
        exit 1
        fi
    fi
fi

unix_sys_path=$($wine winepath -u 'C:\windows\system32' 2> /dev/null)

if [ -z "$unix_sys_path" ]; then
  echo 'Failed to resolve C:\windows\system32.' >&2
  exit 1
fi

ret=0

function removeOverride {
    echo "    [1/2] Removing override... "
    $wine reg delete 'HKEY_CURRENT_USER\Software\Wine\DllOverrides' /v "$1" /f > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Override does not exist, trying next..."
        ret=2
    fi
    local dll="$unix_sys_path/$1.dll"
    echo "    [2/2] Removing link... "
    if [ -h "$dll" ]; then
        out=$(rm "$dll" 2>&1)
        if [ $? -ne 0 ]; then
            ret=2
            echo -e "$out"
        fi
    else
        echo -e "'$dll' is not a link or doesn't exist."
        ret=2
    fi
}

function createOverride {
    echo "    [1/2] Creating override... "
    $wine reg add 'HKEY_CURRENT_USER\Software\Wine\DllOverrides' /v "$1" /d native /f >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "Failed"
        exit 1
    fi
    echo "    [2/2] Creating link to $1.$dll_ext... "
    ln -sf "$nvapi_dir/$lib/$1.$dll_ext" "$unix_sys_path/$1.dll"
    if [ $? -ne 0 ]; then
        echo -e "Failed"
        exit 1
    fi
}

case "$1" in
uninstall)
    fun=removeOverride
    ;;
install)
    fun=createOverride
    ;;
*)
    echo "Unrecognized option: $1"
    echo "Usage: $0 [install|uninstall] [-q|--quiet] [-y|-n]"
    exit 1
    ;;
esac

echo '[1/4] nvcuda :'
$fun nvcuda
echo '[2/4] nvcuvid :'
$fun nvcuvid
echo '[3/4] nvapi :'
$fun nvapi
echo '[4/4] nvencodeapi :'
$fun nvencodeapi
wine="wine64"
lib='lib64'
unix_sys_path=$($wine winepath -u 'C:\windows\system32' 2> /dev/null)
echo '[1/4] 64 bit nvcuda :'
$fun nvcuda
echo '[2/4] 64 bit nvcuvid :'
$fun nvcuvid
echo '[3/4] 64 bit nvapi64 :'
$fun nvapi64
echo '[4/4] 64 bit nvencodeapi64 :'
$fun nvencodeapi64
if [ "$fun" = removeOverride ]; then
   echo "Rebooting prefix!"
   wineboot -u
fi
exit $ret
