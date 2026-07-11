#!/usr/bin/env bash

MODULE_TEMPLATE_DIR="module"
CWD=$(pwd)
TEMP_DIR="temp"
BIN_DIR="bin"
BUILD_DIR="build"
DL_SRCS=("direct" "uptodown" "apkmirror" "archive")

if [ "${GITHUB_TOKEN-}" ]; then GH_HEADER="Authorization: token ${GITHUB_TOKEN}"; else GH_HEADER=; fi
NEXT_VER_CODE=${NEXT_VER_CODE:-$(date +'%Y%m%d')}

toml_prep() {
        if [ ! -f "$1" ]; then return 1; fi
        if [ "${1##*.}" == toml ]; then
                __TOML__=$(python3 -c 'import sys,tomllib,json; print(json.dumps(tomllib.load(sys.stdin.buffer)))' < "$1")
        elif [ "${1##*.}" == json ]; then
                __TOML__=$(cat "$1")
        else abort "config extension not supported"; fi
}
toml_get_table_names() { jq -r -e 'to_entries[] | select(.value | type == "object") | .key' <<<"$__TOML__"; }
toml_get_table_main() { jq -r -e 'to_entries | map(select(.value | type != "object")) | from_entries' <<<"$__TOML__"; }
toml_get_table() { jq -r -e ".\"${1}\"" <<<"$__TOML__"; }
toml_get() {
        local op quote_placeholder=$'\001'
        op=$(jq -r ".\"${2}\" | values" <<<"$1")
        if [ "$op" ]; then
                op="${op#"${op%%[![:space:]]*}"}"
                op="${op%"${op##*[![:space:]]}"}"
                op=${op//\\\'/$quote_placeholder}
                op=${op//"''"/$quote_placeholder}
                op=${op//"'"/'"'}
                op=${op//$quote_placeholder/$'\''}
                echo "$op"
        else return 1; fi
}

pr() { echo -e "\033[0;32m[+] ${1}\033[0m"; }
epr() {
        echo >&2 -e "\033[0;31m[-] ${1}\033[0m"
        if [ "${GITHUB_REPOSITORY-}" ]; then echo >&2 "::error::${1}"; fi
}
wpr() {
        echo >&2 -e "\033[0;33m[!] ${1}\033[0m"
        if [ "${GITHUB_REPOSITORY-}" ]; then echo >&2 "::warning::${1}"; fi
}

_clean_tmp() {
        rm -rf ./${TEMP_DIR}/*tmp.* ./${TEMP_DIR}/*tmp_* ./${TEMP_DIR}/*/*tmp.* ./${TEMP_DIR}/*-temporary-files ./*-temporary-files
}

abort() {
        epr "ABORT: ${1-}"
        _clean_tmp
        trap - SIGTERM SIGINT EXIT
        kill -9 -- -$$ 2>/dev/null
        exit 1
}
java() { env -i java --enable-native-access=ALL-UNNAMED "$@"; }

get_prebuilts() {
        local cli_src=$1 cli_ver=$2 patches_src=$3 patches_ver=$4
        pr "Getting prebuilts (${patches_src%/*})" >&2
        local cl_dir=${patches_src%/*}
        cl_dir=${TEMP_DIR}/${cl_dir,,}-rv
        [ -d "$cl_dir" ] || mkdir -p "$cl_dir"

        for src_ver in "$cli_src CLI $cli_ver cli" "$patches_src Patches $patches_ver patches"; do
                set -- $src_ver
                local src=$1 tag=$2 ver=${3-} fprefix=$4
                local is_dev=false

                if [ "$tag" = "CLI" ]; then
                        local grab_cl=false
                elif [ "$tag" = "Patches" ]; then
                        local grab_cl=true
                else abort unreachable; fi

                local dir=${src%/*}
                dir=${TEMP_DIR}/${dir,,}-rv
                [ -d "$dir" ] || mkdir -p "$dir"

                local rv_rel="https://api.github.com/repos/${src}/releases" name_ver
                if [ "$ver" = "dev" ]; then
                        is_dev=true
                        local resp
                        resp=$(gh_req "$rv_rel" -) || return 1
                        ver=$(jq -e -r '.[0].tag_name' <<<"$resp") || return 1
                        rv_rel="https://api.github.com/repos/${src}/releases/tags/${ver}"
                        name_ver="$ver"
                elif [ "$ver" = "latest" ]; then
                        rv_rel+="/latest"
                        name_ver="*"
                else
                        rv_rel+="/tags/${ver}"
                        name_ver="$ver"
                fi

                local url file tag_name matches
                file=$(find "$dir" -name "*${fprefix}-${name_ver#v}.*" -type f 2>/dev/null)
                if [ "$ver" = "latest" ]; then
                        file=$(grep -v '/[^/]*dev[^/]*$' <<<"$file" | head -1)
                else
                        file=$(grep "/[^/]*${ver#v}[^/]*\$" <<<"$file" | head -1)
                fi
                if [ -z "$file" ]; then
                        local resp asset
                        resp=$(gh_req "$rv_rel" -) || return 1
                        tag_name=$(jq -r '.tag_name' <<<"$resp")

                        if [ "$tag" = "CLI" ]; then
                                if [ "$is_dev" = true ]; then
                                        asset=$(jq -r '
                                                [.assets[]
                                                        | select(.name | endswith(".jar"))
                                                        | select(.name | endswith(".asc") | not)
                                                ] | sort_by(.name) | last // empty' <<<"$resp")
                                else
                                        asset=$(jq -r '
                                                [.assets[]
                                                        | select(.name | endswith(".jar"))
                                                        | select(.name | endswith(".asc") | not)
                                                        | select(.name | test("dev") | not)
                                                ] | sort_by(.name) | last // empty' <<<"$resp")
                                        if [ -z "$asset" ] || [ "$asset" = "null" ]; then
                                                asset=$(jq -r '
                                                        [.assets[]
                                                                | select(.name | endswith(".jar"))
                                                                | select(.name | endswith(".asc") | not)
                                                        ] | sort_by(.name) | last // empty' <<<"$resp")
                                        fi
                                fi
                        else
                                matches=$(jq -e '.assets | map(select(.name | (endswith(".asc") or endswith(".json")) | not))' <<<"$resp")
                                if [ "$(jq 'length' <<<"$matches")" -eq 0 ]; then
                                        wpr "No asset found for ${tag} from ${src}"
                                        return 1
                                elif [ "$(jq 'length' <<<"$matches")" -ne 1 ]; then
                                        wpr "More than 1 asset was found for this release. Falling back to the first one found..."
                                fi
                                asset=$(jq -r '.[0]' <<<"$matches")
                        fi

                        if [ -z "$asset" ] || [ "$asset" = "null" ]; then
                                wpr "No suitable asset found for ${tag} from ${src}"
                                return 1
                        fi

                        url=$(jq -r .url <<<"$asset")
                        name=$(jq -r .name <<<"$asset")
                        file="${dir}/${name}"
                        gh_dl "$file" "$url" >&2 || return 1
                        echo "$tag: $(cut -d/ -f1 <<<"$src")/${name}  " >>"${cl_dir}/changelog.md"
                else
                        grab_cl=false
                        name=$(basename "$file")
                        tag_name=$(cut -d'-' -f3- <<<"$name")
                        tag_name=v${tag_name%.*}
                fi

                echo -n "$file "
        done
        echo
}

get_gitlab_prebuilts() {
        local src=$1 ver=$2
        local proj="${src//\//%2F}"
        local dir="${TEMP_DIR}/${src//\//-}-gl"
        mkdir -p "$dir"

        local resp
        resp=$(req "https://gitlab.com/api/v4/projects/${proj}/releases" -) || {
                epr "Failed to fetch GitLab releases for ${src}"
                return 1
        }

        local tag_name dl_url
        if [ "$ver" = "latest" ] || [ "$ver" = "dev" ]; then
                tag_name=$(jq -r '.[0].tag_name' <<<"$resp")
                dl_url=$(jq -r '.[0].assets.links[] | select(.name | test("\\.mpp$")) | .url' <<<"$resp" | head -1)
        else
                tag_name=$(jq -r --arg v "$ver" '.[] | select(.tag_name == $v or .tag_name == ("v"+$v)) | .tag_name' <<<"$resp" | head -1)
                dl_url=$(jq -r --arg v "$ver" '.[] | select(.tag_name == $v or .tag_name == ("v"+$v)) | .assets.links[] | select(.name | test("\\.mpp$")) | .url' <<<"$resp" | head -1)
        fi

        if [ -z "$dl_url" ] || [ -z "$tag_name" ] || [ "$tag_name" = "null" ]; then
                epr "No .mpp release found for ${src}@${ver}"
                return 1
        fi

        local fname out
        fname=$(awk -F/ '{print $NF}' <<<"$dl_url")
        out="${dir}/${fname}"
        req "$dl_url" "$out" || return 1
        echo "$out $tag_name"
}


set_prebuilts() {
        local arch
        arch=$(uname -m)
        if [ "$arch" = aarch64 ]; then arch=arm64; elif [ "${arch:0:5}" = "armv7" ]; then arch=arm; fi
        HTMLQ="${BIN_DIR}/htmlq"

        CURL_IMP="${BIN_DIR}/curl-imp"
        if [ ! -x "$CURL_IMP" ] || ! grep -q '^imp_targets = \[' "$CURL_IMP" 2>/dev/null; then
                if pip install curl-cffi --break-system-packages -q 2>/dev/null; then
                        FF_VER=$(curl -sf "https://product-details.mozilla.org/1.0/firefox_versions.json" | jq -re '.LATEST_FIREFOX_VERSION' 2>/dev/null || echo "135.0")
                        FF_MAJOR=${FF_VER%%.*}
                        cat > "$CURL_IMP" << PYEOF
#!/usr/bin/env python3
import sys
from curl_cffi import requests

TAKES_VALUE = {
    '-H', '--header', '-A', '--user-agent', '-o', '--output',
    '-c', '--cookie-jar', '-b', '--cookie',
    '--connect-timeout', '--max-time', '--retry', '--retry-delay',
}
FLAGS = {'-L', '--location', '-s', '--silent', '-S', '--show-error',
         '--fail', '-f', '-v', '--verbose', '-k', '--insecure'}

args = sys.argv[1:]
headers, output, url = {}, '-', None
connect_timeout = 30

i = 0
while i < len(args):
    a = args[i]
    if a in TAKES_VALUE and i + 1 < len(args):
        val = args[i + 1]
        if a in ('-H', '--header') and ': ' in val:
            k, v = val.split(': ', 1)
            if k.lower() != 'user-agent':
                headers[k] = v
        elif a in ('-o', '--output'):
            output = val
        elif a == '--connect-timeout':
            try: connect_timeout = float(val)
            except ValueError: pass
        i += 2
    elif a in FLAGS:
        i += 1
    elif not a.startswith('-'):
        url = a; i += 1
    else:
        i += 1

if not url:
    print("curl-imp: no URL specified", file=sys.stderr); sys.exit(1)

timeout = (connect_timeout, 300)

imp_targets = ["firefox${FF_MAJOR}", "firefox135", "firefox120", "firefox110", "firefox"]
r = None
last_err = None
for target in imp_targets:
    try:
        r = requests.get(url, headers=headers, impersonate=target,
                         allow_redirects=True, timeout=timeout)
        break
    except Exception as e:
        last_err = e
        continue

if r is None:
    print(f"curl: (6) {last_err}", file=sys.stderr); sys.exit(6)

if r.status_code >= 400:
    print(f"curl: (22) The requested URL returned error: {r.status_code}", file=sys.stderr)
    sys.exit(22)

data = r.content
if output == '-':
    sys.stdout.buffer.write(data)
else:
    with open(output, 'wb') as f: f.write(data)
PYEOF
                        chmod +x "$CURL_IMP"
                else
                        pr "Warning: curl-cffi unavailable, falling back to system curl"
                        CURL_IMP=""
                fi
        fi
}

check_striplibs() {
        local cli=$1
        local cache_key
        cache_key=$(echo "$cli" | md5sum | cut -d' ' -f1)
        local cache_file="$TEMP_DIR/.striplibs_${cache_key}"
        if [ -f "$cache_file" ]; then
                cat "$cache_file"
                return
        fi
        local out
        out=$(java -jar "$cli" patch 2>&1) || true
        if [[ "$out" == *"--striplibs"* ]]; then
                echo true > "$cache_file"
                echo true
        else
                echo false > "$cache_file"
                echo false
        fi
}

_req() {
        local ip="$1" op="$2"
        shift 2
        local dlp="$op"
        if [ "$op" != - ]; then
                if [ -f "$op" ]; then return 0; fi
                dlp="$(dirname "$op")/tmp.$(basename "$op")"
                if [ -f "$dlp" ]; then
                        while [ -f "$dlp" ]; do sleep 1; done
                        return 0
                fi
        fi
        local _curl="${CURL_IMP:-}"
        [ -x "$_curl" ] || _curl="curl"
        if ! "$_curl" -L -c "$TEMP_DIR/cookie.txt" -b "$TEMP_DIR/cookie.txt" --connect-timeout 10 --retry 1 --fail -s -S "$@" "$ip" -o "$dlp"; then
                epr "Request failed: $ip"
                return 1
        fi
        if [ "$dlp" != - ]; then
                mv -f "$dlp" "$op"
        fi
}
ua() {
        local ver major
        ver=$(curl -sf "https://product-details.mozilla.org/1.0/firefox_versions.json" | jq -re '.LATEST_FIREFOX_VERSION') || ver="135.0"
        major=${ver%%.*}
        echo "Mozilla/5.0 (X11; Linux x86_64; rv:${major}.0) Gecko/20100101 Firefox/${major}.0"
}
_UA=""
req() { if [ -z "$_UA" ]; then _UA=$(ua); fi; _req "$1" "$2" -A "$_UA"; }

gh_req() {
        local ip="$1" op="$2"
        if [ "$op" = - ]; then
                curl -L --connect-timeout 10 --retry 1 --fail -s -S \
                        -H "$GH_HEADER" -H "Accept: application/vnd.github+json" "$ip"
        else
                if [ -f "$op" ]; then return 0; fi
                local dlp="$(dirname "$op")/tmp.$(basename "$op")"
                curl -L --connect-timeout 10 --retry 1 --fail -s -S \
                        -H "$GH_HEADER" -H "Accept: application/vnd.github+json" \
                        "$ip" -o "$dlp" && mv -f "$dlp" "$op"
        fi
}
gh_dl() {
        if [ ! -f "$1" ]; then
                pr "Getting '$1' from '$2'"
                if [ -f "$1" ]; then return 0; fi
                local dlp="$(dirname "$1")/tmp.$(basename "$1")"
                curl -L --connect-timeout 10 --retry 1 --fail -s -S \
                        -H "$GH_HEADER" -H "Accept: application/octet-stream" \
                        "$2" -o "$dlp" && mv -f "$dlp" "$1"
        fi
}

log() { echo -e "$1  " >>"build.md"; }
get_highest_ver() {
        local vers m
        vers=$(tee)
        m=$(head -1 <<<"$vers")
        if ! semver_validate "$m"; then echo "$m"; else sort -s -t- -k1,1Vr <<<"$vers" | head -1; fi
}
semver_validate() {
        local a="${1%-*}"
        local a="${a#v}"
        local ac="${a//[.0-9]/}"
        [ ${#ac} = 0 ]
}
get_patch_last_supported_ver() {
        local list_patches=$1 pkg_name=$2 inc_sel=$3 _exc_sel=$4 _exclusive=$5
        local op
        if [ "$inc_sel" ]; then
                if ! op=$(awk '{$1=$1}1' <<<"$list_patches"); then
                        epr "list-patches: '$op'"
                        return 1
                fi
                local ver vers="" NL=$'\n'
                while IFS= read -r line; do
                        line="${line:1:${#line}-2}"
                        ver=$(sed -n "/^Name: $line\$/,/^\$/p" <<<"$op" | sed -n "/^Compatible versions:\$/,/^\$/p" | tail -n +2)
                        vers=${ver}${NL}
                done <<<"$(list_args "$inc_sel")"
                vers=$(awk '{$1=$1}1' <<<"$vers")
                if [ "$vers" ]; then
                        get_highest_ver <<<"$vers"
                        return
                fi
        fi
        op=$(patches_list_versions "$cli_jar" "$patches_jar" "$pkg_name") || return 1
        op=$(sed -n '/Most common compatible versions:/,$p' <<<"$op" | sed '1d' | awk '{$1=$1}1')
        if [ "$op" = "Any" ]; then return; fi
        pcount=$(head -1 <<<"$op") pcount=${pcount#*(} pcount=${pcount% *}
        if [ -z "$pcount" ]; then
                av_apps=$(java -jar "$cli_jar" list-versions "$patches_jar" 2>&1 | awk '/Package name:/ { printf "%s\x27%s\x27", sep, $NF; sep=", " } END { print "" }')
                epr "No patch versions found for '$pkg_name' in this patches source!\nAvailable applications found: $av_apps"
                return 1
        fi
        grep -F "($pcount patch" <<<"$op" | sed 's/ (.* patch.*//' | get_highest_ver || return 1
}

patches_list_versions() {
        local cli_jar=$1 patches_jar=$2 pkg_name=$3 op cmd
        local cmd_base="java -jar '$cli_jar' list-versions"

        cmd="${cmd_base} --patches='$patches_jar' -f '$pkg_name'"
        if op=$(eval "$cmd" 2>&1); then
                echo "$op"
                return
        fi

        cmd="${cmd_base} '$patches_jar' -f '$pkg_name'"
        if op=$(eval "$cmd" 2>&1); then
                echo "$op"
                return
        fi

        epr "Could not list versions $cli_jar: '$op'"
        return 1
}
patches_list() {
        local cli_jar=$1 patches_jar=$2 pkg_name=$3 op
        if ! op=$(java -jar "$cli_jar" list-patches -p "$patches_jar" --filter-package-name "$pkg_name" --versions --packages -b 2>&1); then
                if ! op=$(java -jar "$cli_jar" list-patches --patches "$patches_jar" -f "$pkg_name" --with-versions --with-packages 2>&1); then
                        epr "Could not get patches list $cli_jar: '$op'"
                        return 1
                fi

        fi
        echo "$op"
}

isoneof() {
        local i=$1 v
        shift
        for v; do [ "$v" = "$i" ] && return 0; done
        return 1
}

merge_splits() {
        local bundle=$1 output=$2 target_arch=${3:-arm64-v8a}
        pr "Merging splits"

        if [ ! -f "$TEMP_DIR/apkeditor.jar" ]; then
                local apkeditor_asset
                apkeditor_asset=$(gh_req "https://api.github.com/repos/REAndroid/APKEditor/releases/latest" - \
                        | jq -r '.assets[] | select(.name | endswith(".jar")) | .browser_download_url' | head -1) || {
                        epr "Failed to get APKEditor download URL"
                        return 1
                }
                if [ -z "$apkeditor_asset" ] || [ "$apkeditor_asset" = "null" ]; then
                        epr "No APKEditor jar found in latest release"
                        return 1
                fi
                pr "Downloading APKEditor: $apkeditor_asset"
                req "$apkeditor_asset" "$TEMP_DIR/apkeditor.jar" || return 1
        fi

        pr "Bundle contents:"
        if ! unzip -l "${bundle}" >/dev/null 2>&1; then
                epr "Bundle is not a valid zip, removing: ${bundle}"
                rm -f "${bundle}"
                return 1
        fi
        local apk_count
        apk_count=$(unzip -l "${bundle}" 2>/dev/null | grep -ic '\.apk$') || apk_count=0
        if [ "$apk_count" -eq 0 ]; then
                epr "Bundle contains no APK files, removing: ${bundle}"
                rm -f "${bundle}"
                return 1
        fi
        unzip -l "${bundle}" 2>/dev/null | grep -i '\.apk$' | awk '{print "  " $NF " (" $1 " bytes)"}' || true

        pr "Stripping non-arm64 arch splits"
        local remove_arch
        remove_arch=$(unzip -l "${bundle}" 2>/dev/null \
                | grep -oP '[^ ]*(?:split_)?config[._](?:armeabi_v7a|armeabi-v7a|x86_64|x86)\.apk') || true
        if [ -n "$remove_arch" ]; then
                pr "Removing arch splits: $(echo "$remove_arch" | tr '\n' ' ')"
                zip -d "${bundle}" $remove_arch 2>/dev/null || true
        fi

        local dpi_splits
        dpi_splits=$(unzip -l "${bundle}" 2>/dev/null \
                | grep -oP '[^ ]*(?:split_)?config[._][a-z]*dpi\.apk') || true
        if [ -n "$dpi_splits" ]; then
                local dpi_count
                dpi_count=$(echo "$dpi_splits" | wc -l)
                if [ "$dpi_count" -gt 1 ]; then
                        local remove_dpi
                        remove_dpi=$(echo "$dpi_splits" | grep -v -P '[._]xxhdpi\.apk$') || true
                        if [ -n "$remove_dpi" ]; then
                                pr "Removing $(echo "$remove_dpi" | wc -l) DPI splits, keeping xxhdpi"
                                zip -d "${bundle}" $remove_dpi 2>/dev/null || true
                        fi
                fi
        fi

        local lang_splits
        lang_splits=$(unzip -l "${bundle}" 2>/dev/null \
                | grep -oP '[^ ]*(?:split_)?config[._][a-z]{2,3}(?:[_-]r?[A-Z]{2})?\.apk' \
                | grep -v -E '(arm64|armeabi|x86|dpi|base)') || true
        if [ -n "$lang_splits" ]; then
                local remove_langs
                remove_langs=$(echo "$lang_splits" | grep -v -E '[._](en|fr|ar)\.apk$') || true
                if [ -n "$remove_langs" ]; then
                        local lang_count
                        lang_count=$(echo "$remove_langs" | wc -l)
                        pr "Removing ${lang_count} language splits, keeping en/fr/ar"
                        zip -d "${bundle}" $remove_langs 2>/dev/null || true
                fi
        fi

        local i18n_splits
        i18n_splits=$(unzip -l "${bundle}" 2>/dev/null \
                | grep -oP '[^ ]*i18n_[a-z]{2}(_[A-Z]{2})?\.apk') || true
        if [ -n "$i18n_splits" ]; then
                local remove_i18n
                remove_i18n=$(echo "$i18n_splits" | grep -v -E 'i18n_(en|fr|ar)') || true
                if [ -n "$remove_i18n" ]; then
                        local i18n_count
                        i18n_count=$(echo "$remove_i18n" | wc -l)
                        pr "Removing ${i18n_count} i18n splits, keeping en/fr/ar"
                        zip -d "${bundle}" $remove_i18n 2>/dev/null || true
                fi
        fi

        pr "Bundle after stripping:"
        unzip -l "${bundle}" 2>/dev/null | grep -i '\.apk$' | awk '{print "  " $NF " (" $1 " bytes)"}' || true

        if ! OP=$(java -jar "$TEMP_DIR/apkeditor.jar" merge -i "${bundle}" -o "${bundle}.merged.apk" -clean-meta -f 2>&1); then
                epr "Apkeditor ERROR: $OP"
                return 1
        fi

        local merged_size
        merged_size=$(stat -c%s "${bundle}.merged.apk" 2>/dev/null) || true
        pr "Merged APK size: $(( merged_size / 1048576 ))MB (${merged_size} bytes)"

        cp "${bundle}.merged.apk" "${output}" || return 1
        rm -f "${bundle}.merged.apk" || :
}

apkmirror_search() {
        local resp="$1" dpi="$2" arch="$3" apk_bundle="$4"
        local dlurl="" node app_table emptyCheck

        local apparch=('universal' 'noarch' 'arm64-v8a + armeabi-v7a' 'arm64-v8a')

        local appdpi=("nodpi" "anydpi")
        if [ "$dpi" ]; then
                appdpi+=($dpi)
        fi

        for ((n = 1; n < 40; n++)); do
                node=$($HTMLQ "div.table-row.headerFont:nth-last-child($n)" -r "span:nth-child(n+3)" <<<"$resp")
                if [ -z "$node" ]; then break; fi
                emptyCheck=$($HTMLQ -t -i "div.table-cell:nth-child(1) > a:nth-child(1)" <<<"$node" | xargs)
                if [ -z "$emptyCheck" ]; then break; fi
                app_table=$($HTMLQ --text --ignore-whitespace <<<"$node")
                if [ "$(sed -n 3p <<<"$app_table")" != "$apk_bundle" ]; then continue; fi
                dlurl=$($HTMLQ --base https://www.apkmirror.com --attributes href "div:nth-child(1) > a:nth-child(1)" <<<"$node")
                if isoneof "$(sed -n 6p <<<"$app_table")" "${appdpi[@]}" &&
                        isoneof "$(sed -n 4p <<<"$app_table")" "${apparch[@]}"; then
                        echo "$dlurl"
                        return 0
                fi
        done
        if [ "$n" -eq 2 ] && [ "$dlurl" ]; then
                echo "$dlurl"
                return 0
        fi
        return 1
}
dl_apkmirror() {
        local url=$1 version=${2// /-} output=$3 arch=$4 dpi=$5 is_bundle=false
        if [ -f "${output}.apkm" ]; then
                merge_splits "${output}.apkm" "${output}" "${arch}"
                return 0
        fi
        local resp node app_table apkmname dlurl=""
        apkmname=$($HTMLQ "h1.marginZero" --text <<<"$__APKMIRROR_RESP__")
        apkmname="${apkmname,,}" apkmname="${apkmname// /-}" apkmname="${apkmname//[^a-z0-9-]/}"
        url="${url}/${apkmname}-${version//./-}-release/"
        resp=$(req "$url" -) || return 1
        node=$($HTMLQ "div.table-row.headerFont:nth-last-child(1)" -r "span:nth-child(n+3)" <<<"$resp")
        if [ "$node" ]; then
                for type in APK BUNDLE; do
                        if dlurl=$(apkmirror_search "$resp" "$dpi" "$arch" "$type"); then
                                if [ "$type" = "BUNDLE" ]; then
                                        is_bundle=true
                                else is_bundle=false; fi
                                break
                        fi
                done
                if [ -z "$dlurl" ]; then return 1; fi
                resp=$(req "$dlurl" -)
        fi
        url=$(echo "$resp" | $HTMLQ --base https://www.apkmirror.com --attributes href "a.btn") || return 1
        [ -z "$url" ] && { epr "Could not extract download page URL from APKMirror"; return 1; }
        url=$(req "$url" - | $HTMLQ --base https://www.apkmirror.com --attributes href "span > a[rel = nofollow]")
        [ -z "$url" ] && { epr "Could not extract direct download URL from APKMirror"; return 1; }
        if [ "$is_bundle" = true ]; then
                req "$url" "${output}.apkm" || return 1
                merge_splits "${output}.apkm" "${output}" "${arch}"
        else
                req "$url" "${output}" || return 1
        fi
}
get_apkmirror_vers() {
        local vers="" page_vers stable_vers=""
        for page in 1 2 3; do
                local apkm_resp
                apkm_resp=$(req "https://www.apkmirror.com/uploads/?appcategory=${__APKMIRROR_CAT__}&page=${page}" -) || break
                page_vers=$(sed -n 's;.*Version:</span><span class="infoSlide-value">\(.*\) </span>.*;\1;p' <<<"$apkm_resp" | awk '{$1=$1}1')
                [ -z "$page_vers" ] && break
                local IFS=$'\n'
                local v
                for v in $page_vers; do
                        grep -iq "${v} \(beta\|alpha\)" <<<"$apkm_resp" || stable_vers="${stable_vers}${stable_vers:+$'\n'}${v}"
                done
        done
        echo "$stable_vers"
}
get_apkmirror_pkg_name() { sed -n 's;.*id=\(.*\)" class="accent_color.*;\1;p' <<<"$__APKMIRROR_RESP__"; }
get_apkmirror_resp() {
        __APKMIRROR_RESP__=$(req "${1}" -) || return 1
        __APKMIRROR_CAT__="${1##*/}"
}

get_uptodown_resp() {
        __UPTODOWN_RESP__=$(req "${1}/versions" -) || return 1
        __UPTODOWN_RESP_PKG__=$(req "${1}/download" -) || return 1
}
get_uptodown_vers() { $HTMLQ --text ".version" <<<"$__UPTODOWN_RESP__"; }
dl_uptodown() {
        local uptodown_dlurl=$1 version=$2 output=$3 arch=$4 _dpi=$5

        local apparch=('arm64-v8a, armeabi-v7a, x86_64' 'arm64-v8a, armeabi-v7a, x86, x86_64' 'arm64-v8a, armeabi-v7a' 'arm64-v8a')

        local op resp data_code
        data_code=$($HTMLQ "#detail-app-name" --attributes data-code <<<"$__UPTODOWN_RESP__")
        local versionURL=""
        local is_bundle=false
        for i in {1..20}; do
                resp=$(req "${uptodown_dlurl}/apps/${data_code}/versions/${i}" -) || continue
                if ! op=$(jq -e -r ".data | map(select(.version == \"${version}\")) | .[0]" <<<"$resp" 2>/dev/null); then
                        continue
                fi
                if [ "$(jq -e -r ".kindFile" <<<"$op" 2>/dev/null)" = "xapk" ]; then is_bundle=true; fi
                if versionURL=$(jq -e -r '.versionURL' <<<"$op" 2>/dev/null); then break; else continue; fi
        done
        if [ -z "$versionURL" ]; then return 1; fi
        versionURL=$(jq -e -r '.url + "/" + .extraURL + "/" + (.versionID | tostring)' <<<"$versionURL" 2>/dev/null) || return 1
        resp=$(req "$versionURL" -) || return 1

        local data_version files node_arch="" data_file_id node_class
        data_version=$($HTMLQ '.button.variants' --attributes data-version <<<"$resp") || return 1
        if [ "$data_version" ]; then
                files=$(req "${uptodown_dlurl%/*}/app/${data_code}/version/${data_version}/files" - | jq -e -r .content) || return 1
                for ((n = 1; n < 12; n += 1)); do
                        node_class=$($HTMLQ -i -t ".content > :nth-child($n)" --attributes class <<<"$files") || return 1
                        if [ "$node_class" != "variant" ]; then
                                node_arch=$($HTMLQ -i -t ".content > :nth-child($n)" <<<"$files" | xargs) || return 1
                                continue
                        fi
                        if [ -z "$node_arch" ]; then return 1; fi
                        if ! isoneof "$node_arch" "${apparch[@]}"; then continue; fi

                        file_type=$($HTMLQ -i -t ".content > :nth-child($n) > .v-file > span" <<<"$files") || return 1
                        if [ "$file_type" = "xapk" ]; then is_bundle=true; else is_bundle=false; fi
                        data_file_id=$($HTMLQ ".content > :nth-child($n) > .v-report" --attributes data-file-id <<<"$files") || return 1
                        resp=$(req "${uptodown_dlurl}/download/${data_file_id}-x" -)
                        break
                done
                if [ $n -eq 12 ]; then return 1; fi
        fi
        local data_url
        data_url=$($HTMLQ "#detail-download-button" --attributes data-url <<<"$resp") || return 1
        if [ $is_bundle = true ]; then
                req "https://dw.uptodown.com/dwn/${data_url}" "$output.apkm" || return 1
                merge_splits "${output}.apkm" "${output}" "${arch}"
        else
                req "https://dw.uptodown.com/dwn/${data_url}" "$output"
        fi
}
get_uptodown_pkg_name() { $HTMLQ --text "tr.full:nth-child(1) > td:nth-child(3)" <<<"$__UPTODOWN_RESP_PKG__"; }

dl_archive() {
        local url=$1 version=$2 output=$3 arch=$4
        local path version=${version// /}

        if [ -f "${output}.apkm" ]; then
                merge_splits "${output}.apkm" "$output" "${arch}"
                return 0
        fi

        path=$(grep -m1 "${version#v}-${arch// /}" <<<"$__ARCHIVE_RESP__") || return 1
        if [ "${path##*.}" = "apkm" ]; then
                req "${url}/${path}" "${output}.apkm" || return 1
                merge_splits "${output}.apkm" "$output" "${arch}"
        else
                req "${url}/${path}" "$output" || return 1
        fi
}
get_archive_resp() {
        local r
        r=$(req "$1" -)
        if [ -z "$r" ]; then return 1; else __ARCHIVE_RESP__=$(sed -n 's;^<a href="\(.*\)"[^"]*;\1;p' <<<"$r"); fi
        __ARCHIVE_PKG_NAME__=$(awk -F/ '{print $NF}' <<<"$1")
}
get_archive_vers() { sed 's/^[^-]*-//;s/-\(all\|arm64-v8a\|arm-v7a\)\.apk//g' <<<"$__ARCHIVE_RESP__"; }
get_archive_pkg_name() { echo "$__ARCHIVE_PKG_NAME__"; }

dl_direct() {
        local url=$1 version=${2// /-} output=$3 arch=$4 _dpi=$5
        if ! grep -q "${version_f#v}-${arch// /}" <<<"$url"; then
                epr "Given direct-dlurl for $output is not compatible. Set proper 'arch' and 'version' options."
                return 1
        fi
        if [[ "$url" == *.apkm ]]; then
                req "$url" "${output}.apkm" || return 1
                merge_splits "${output}.apkm" "${output}" "${arch}"
        else
                req "$url" "${output}" || return 1
        fi
}
get_direct_vers() { cut -d- -f2 <<<"$__DIRECT_APKNAME__"; }
get_direct_pkg_name() { cut -d- -f1 <<<"$__DIRECT_APKNAME__"; }
get_direct_resp() { __DIRECT_APKNAME__=$(awk -F/ '{print $NF}' <<<"$1"); }

patch_apk() {
        local stock_input=$1 patched_apk=$2 patcher_args=$3 cli_jar=$4 patches_jar=$5 shim_jar=${6-}
        local tmp_files
        tmp_files="$(pwd)/$(mktemp -d -p "$TEMP_DIR")"
        local patches_arg="--patches '$patches_jar'"
        [ -n "$shim_jar" ] && patches_arg="--patches '$shim_jar' --patches '$patches_jar'"
        local cmd="java -jar '$cli_jar' patch '$stock_input' -o '$patched_apk' $patches_arg --keystore=ks.keystore \
--keystore-entry-password=987654321 --keystore-password=987654321 --signer=DrSexo --keystore-entry-alias=DrSexo -t '$tmp_files' $patcher_args"
        pr "$cmd"
        if eval "$cmd"; then
                [ -f "$patched_apk" ]
        else
                rm "$patched_apk" 2>/dev/null || :
                return 1
        fi
}

dl_stock_apk() {
        local stock_apk=$1 version=$2 arch=$3 dpi=$4 table=$5
        shift 5

        if [ -f "$stock_apk" ]; then return 0; fi

        local dl_p
        for dl_p in "${DL_SRCS[@]}"; do
                if [ -z "${args[${dl_p}_dlurl]}" ]; then continue; fi
                pr "Downloading '${table}' from '${dl_p}'"
                if ! isoneof "$dl_p" "${tried_dl[@]}"; then
                        if ! get_${dl_p}_resp "${args[${dl_p}_dlurl]}"; then
                                epr "Could not get '${table}' from '${dl_p}'"
                                continue
                        fi
                fi
                if dl_${dl_p} "${args[${dl_p}_dlurl]}" "$version" "$stock_apk" "$arch" "$dpi"; then
                        return 0
                fi
                epr "Could not download '${table}' from '${dl_p}' with version '${version}', arch '${arch}'"
        done
        return 1
}

get_sorted_versions() {
        local dl_from=$1
        local all_vers
        all_vers=$(get_"${dl_from}"_vers) || return 1
        all_vers=$(grep -iv '\(beta\|alpha\)' <<<"$all_vers" || echo "$all_vers")
        sort -rV <<<"$all_vers" | awk '!seen[$0]++'
}

extract_cli_version() {
        local cli_base
        cli_base=$(basename "$1")
        echo "$cli_base" | sed 's/.*cli-//; s/-all\.jar$//'
}

extract_patches_version() {
        basename "$1" | sed -E 's/.*patches-//; s/\.[^.]+$//'
}

build_rv() {
        eval "declare -A args=${1#*=}"
        local version="" pkg_name=""
        local mode_arg=${args[build_mode]} version_mode=${args[version]}
        local app_name=${args[app_name]}
        local app_name_l=${app_name,,}
        app_name_l=${app_name_l// /-}
        local table=${args[table]}
        local dl_from=${args[dl_from]}
        local arch="arm64-v8a"
        local arch_f="arm64-v8a"
        local riplib=${args[riplib]}

        local p_patcher_args=()
        if [ "${args[excluded_patches]}" ]; then p_patcher_args+=("$(join_args "${args[excluded_patches]}" -d)"); fi
        if [ "${args[included_patches]}" ]; then p_patcher_args+=("$(join_args "${args[included_patches]}" -e)"); fi
        [ "${args[exclusive_patches]}" = true ] && p_patcher_args+=("--exclusive")

        local tried_dl=()
        for dl_p in "${DL_SRCS[@]}"; do
                if [ -z "${args[${dl_p}_dlurl]}" ]; then continue; fi
                if ! get_${dl_p}_resp "${args[${dl_p}_dlurl]}"; then
                        args[${dl_p}_dlurl]=""
                        continue
                fi
                if [ -z "${args[pkg_name]}" ]; then
                        if ! pkg_name=$(get_"${dl_p}"_pkg_name); then
                                args[${dl_p}_dlurl]=""
                                continue
                        fi
                fi
                tried_dl+=("$dl_p")
                dl_from=$dl_p
                break
        done
        if [ "${args[pkg_name]}" ]; then
                pkg_name="${args[pkg_name]}"
        fi
        if [ -z "$pkg_name" ]; then
                epr "empty pkg name, not building ${table}."
                echo "${table}|FAILED|Empty package name" >> "$TEMP_DIR/build_failed.log"
                return 0
        fi
        pr "Package name of '${table}' is '$pkg_name'"

        local cli_jar="${args[cli]}"
        local patches_jar="${args[ptjar]}"
        local list_patches
        list_patches=$(patches_list "$cli_jar" "$patches_jar" "$pkg_name") || return 1
        local get_latest_ver=false
        local use_version_fallback=false
        if [ "$version_mode" = auto ]; then
                if ! version=$(get_patch_last_supported_ver "$list_patches" "$pkg_name" \
                        "${args[included_patches]}" "${args[excluded_patches]}" "${args[exclusive_patches]}"); then
                        echo "${table}|FAILED|Could not determine version" >> "$TEMP_DIR/build_failed.log"
                        return 0
                elif [ -z "$version" ]; then get_latest_ver=true; fi
        elif [ "$version_mode" = "latest" ]; then
                get_latest_ver=true
                use_version_fallback=true
                p_patcher_args+=("-f")
        else
                version=$version_mode
                p_patcher_args+=("-f")
        fi
        if [ $get_latest_ver = true ]; then
                __AAV__="false"
                pkgvers=$(get_"${dl_from}"_vers) || true
                version=$(get_highest_ver <<<"$pkgvers") || version=$(head -1 <<<"$pkgvers") || true
        fi
        if [ -z "$version" ]; then
                epr "empty version, not building ${table}."
                echo "${table}|FAILED|Empty version" >> "$TEMP_DIR/build_failed.log"
                return 0
        fi

        if [ "$mode_arg" = module ]; then
                build_mode_arr=(module)
        elif [ "$mode_arg" = apk ]; then
                build_mode_arr=(apk)
        elif [ "$mode_arg" = both ]; then
                build_mode_arr=(apk module)
        fi

        pr "Choosing version '${version}' for ${table}"
        local version_f=${version// /}
        version_f=${version_f#v}
        local stock_apk="${TEMP_DIR}/${pkg_name}-${version_f}-${arch_f}.apk"

        local dl_attempt=0 dl_max_attempts=3 dl_ok=false
        while [ "$dl_attempt" -lt "$dl_max_attempts" ]; do
                if dl_stock_apk "$stock_apk" "$version" "$arch" "${args[dpi]}" "$table"; then
                        dl_ok=true
                        break
                fi
                dl_attempt=$((dl_attempt + 1))
                if [ "$dl_attempt" -lt "$dl_max_attempts" ]; then
                        pr "Download attempt $dl_attempt failed for '${table}', retrying in 30s..."
                        sleep 30
                        for dl_p in "${DL_SRCS[@]}"; do
                                if [ -n "${args[${dl_p}_dlurl]}" ]; then
                                        get_${dl_p}_resp "${args[${dl_p}_dlurl]}" 2>/dev/null || true
                                fi
                        done
                fi
        done
        if [ "$dl_ok" != true ]; then
                epr "Stock APK not found for '${table}' after ${dl_max_attempts} attempts"
                echo "${table}|FAILED|Download failed" >> "$TEMP_DIR/build_failed.log"
                return 0
        fi
        log "${table}: ${version}"

        local microg_patch disable_psu_patch
        microg_patch=$(grep "^Name: " <<<"$list_patches" | grep -i "gmscore\|microg" || :) microg_patch=${microg_patch#*: }
        disable_psu_patch=$(grep "^Name: " <<<"$list_patches" | grep -i "disable play store updates" || :) disable_psu_patch=${disable_psu_patch#*: }
        for _auto_patch in "$microg_patch" "$disable_psu_patch"; do
                [ -z "$_auto_patch" ] && continue
                if [[ ${p_patcher_args[*]} == *"${_auto_patch}"* ]]; then
                        wpr "You can't include/exclude '$_auto_patch' patch as that's done by builder automatically."
                        p_patcher_args=("${p_patcher_args[@]//-[ei] ${_auto_patch}/}")
                        p_patcher_args=("${p_patcher_args[@]//-[ei] '${_auto_patch}'/}")
                fi
        done

        local patcher_args patched_apk build_mode
        local rv_brand_f=${args[rv_brand],,}
        rv_brand_f=${rv_brand_f// /-}
        if [ "${args[patcher_args]}" ]; then p_patcher_args+=("${args[patcher_args]}"); fi

        local build_success=false
        for build_mode in "${build_mode_arr[@]}"; do
                patcher_args=("${p_patcher_args[@]}")
                pr "Building '${table}' in '$build_mode' mode"
                if [ -n "$microg_patch" ]; then
                        patched_apk="${TEMP_DIR}/${app_name_l}-${rv_brand_f}-${version_f}-${arch_f}-${build_mode}.apk"
                else
                        patched_apk="${TEMP_DIR}/${app_name_l}-${rv_brand_f}-${version_f}-${arch_f}.apk"
                fi
                if [ -n "$microg_patch" ]; then
                        if [ "$build_mode" = apk ]; then
                                patcher_args+=("-e \"${microg_patch}\"")
                        elif [ "$build_mode" = module ]; then
                                patcher_args+=("-d \"${microg_patch}\"")
                        fi
                fi
                if [ -n "$disable_psu_patch" ]; then
                        patcher_args+=("-e \"${disable_psu_patch}\"")
                fi

                if [ "$riplib" = true ] && [ "${args[cli_supports_striplibs]}" = true ]; then
                        patcher_args+=("--striplibs arm64-v8a")
                fi

                local stock_apk_to_patch="${stock_apk}.stripped.apk"
                cp -f "$stock_apk" "$stock_apk_to_patch"
                if [ "$build_mode" = module ]; then
                        zip -d "$stock_apk_to_patch" "lib/*" >/dev/null 2>&1 || :
                else
                        zip -d "$stock_apk_to_patch" "lib/armeabi-v7a/*" "lib/x86_64/*" "lib/x86/*" >/dev/null 2>&1 || :
                fi

                local apk_output="${BUILD_DIR}/${app_name_l}-${rv_brand_f}-v${version_f}-${arch_f}.apk"
                if [ "${NORB:-}" != true ] || { [ ! -f "$patched_apk" ] && [ ! -f "$apk_output" ]; }; then
                        if ! patch_apk "$stock_apk_to_patch" "$patched_apk" "${patcher_args[*]}" "${args[cli]}" "${args[ptjar]}" "${args[shim_jar]-}"; then
                                rm -f "$stock_apk_to_patch"
                                if [ "$use_version_fallback" = true ] && [ "$build_mode" = "${build_mode_arr[0]}" ]; then
                                        pr "Patching failed for '${table}' v${version_f}, trying older versions..."
                                        local fallback_ok=false
                                        local fallback_count=0
                                        local max_fallbacks=5
                                        local sorted_vers
                                        sorted_vers=$(get_sorted_versions "$dl_from") || true

                                        if [ -n "$sorted_vers" ]; then
                                                while IFS= read -r fallback_ver; do
                                                        [ -z "$fallback_ver" ] && continue
                                                        [ "$fallback_ver" = "$version" ] && continue

                                                        fallback_count=$((fallback_count + 1))
                                                        if [ "$fallback_count" -gt "$max_fallbacks" ]; then
                                                                epr "Reached maximum fallback attempts (${max_fallbacks}) for '${table}'"
                                                                break
                                                        fi

                                                        pr "Fallback ${fallback_count}/${max_fallbacks}: trying v${fallback_ver} for ${table}"
                                                        local fb_version_f=${fallback_ver// /}
                                                        fb_version_f=${fb_version_f#v}
                                                        local fb_stock="${TEMP_DIR}/${pkg_name}-${fb_version_f}-${arch_f}.apk"
                                                        local fb_patched
                                                        if [ -n "$microg_patch" ]; then
                                                                fb_patched="${TEMP_DIR}/${app_name_l}-${rv_brand_f}-${fb_version_f}-${arch_f}-${build_mode}.apk"
                                                        else
                                                                fb_patched="${TEMP_DIR}/${app_name_l}-${rv_brand_f}-${fb_version_f}-${arch_f}.apk"
                                                        fi

                                                        if ! dl_stock_apk "$fb_stock" "$fallback_ver" "$arch" "${args[dpi]}" "$table"; then
                                                                epr "Could not download v${fallback_ver}, skipping"
                                                                continue
                                                        fi

                                                        local fb_stripped="${fb_stock}.stripped.apk"
                                                        cp -f "$fb_stock" "$fb_stripped"
                                                        if [ "$build_mode" = module ]; then
                                                                zip -d "$fb_stripped" "lib/*" >/dev/null 2>&1 || :
                                                        else
                                                                zip -d "$fb_stripped" "lib/armeabi-v7a/*" "lib/x86_64/*" "lib/x86/*" >/dev/null 2>&1 || :
                                                        fi

                                                        if patch_apk "$fb_stripped" "$fb_patched" "${patcher_args[*]}" "${args[cli]}" "${args[ptjar]}" "${args[shim_jar]-}"; then
                                                                rm -f "$fb_stripped"
                                                                pr "Fallback succeeded: v${fallback_ver} for ${table}"
                                                                version="$fallback_ver"
                                                                version_f="$fb_version_f"
                                                                stock_apk="$fb_stock"
                                                                patched_apk="$fb_patched"
                                                                fallback_ok=true
                                                                break
                                                        fi
                                                        rm -f "$fb_stripped"
                                                        epr "Fallback v${fallback_ver} also failed for '${table}'"
                                                done <<<"$sorted_vers"
                                        fi

                                        if [ "$fallback_ok" = false ]; then
                                                epr "All fallback versions failed for '${table}' (tried ${fallback_count})"
                                                echo "${table}|FAILED|All versions failed (tried ${fallback_count})" >> "$TEMP_DIR/build_failed.log"
                                                return 0
                                        fi
                                else
                                        epr "Building '${table}' failed!"
                                        continue
                                fi
                        else
                                rm -f "$stock_apk_to_patch"
                        fi
                else
                        rm -f "$stock_apk_to_patch"
                fi

                build_success=true
                if [ -f "$patched_apk" ]; then
                        local patched_size
                        patched_size=$(stat -c%s "$patched_apk" 2>/dev/null) || true
                        [ -n "$patched_size" ] && pr "Patched APK size: $(( patched_size / 1048576 ))MB (${patched_size} bytes)"
                fi
                if [ "$build_mode" = apk ]; then
                        local apk_output="${BUILD_DIR}/${app_name_l}-${rv_brand_f}-v${version_f}-${arch_f}.apk"
                        if [ "${NORB:-}" != true ] || { [ ! -f "$patched_apk" ] && [ ! -f "$apk_output" ]; }; then
                                mv -f "$patched_apk" "$apk_output"
                        else
                                cp -f "$patched_apk" "$apk_output"
                        fi
                        pr "Built ${table} (non-root): '${apk_output}'"
                        continue
                fi
                local base_template
                base_template=$(mktemp -d -p "$TEMP_DIR")
                cp -a $MODULE_TEMPLATE_DIR/. "$base_template"
                [ -f "banner.jpg" ] && cp -f "banner.jpg" "$base_template/" || true

                local upj="${table,,}-update.json"
                module_config "$base_template" "$pkg_name" "$version" "$arch"

                local patches_ver
                patches_ver=$(extract_patches_version "${args[ptjar]}")
                module_prop \
                        "${args[module_prop_name]}" \
                        "${app_name} ${args[rv_brand]}" \
                        "${version} (patches ${patches_ver})" \
                        "${app_name} ${args[rv_brand]} module" \
                        "https://raw.githubusercontent.com/${GITHUB_REPOSITORY-}/update/${upj}" \
                        "$base_template"

                local module_output="${app_name_l}-${rv_brand_f}-module-v${version_f}-${arch_f}.zip"
                pr "Packing module ${table}"
                cp -f "$patched_apk" "${base_template}/base.apk"

                if [ "${args[include_stock]}" != "disable" ]; then
                        mkdir -p "${base_template}/stock/"
                        if [ "${args[include_stock]}" = "merged" ]; then
                                cp -f "$stock_apk" "${base_template}/stock/base.apk"
                        elif [ "${args[include_stock]}" = "split" ]; then
                                if [ ! -f "${stock_apk}.apkm" ]; then
                                        epr "Cannot include as 'split' because stock apk of $table_name is not a bundle"
                                        return 0
                                fi
                                unzip -j "${stock_apk}.apkm" '*.apk' -x '*x86_64.apk' -x '*x86.apk' -x '*armeabi_v7a.apk' -d "${base_template}/stock/" >/dev/null 2>&1
                        fi
                fi
                pushd >/dev/null "$base_template" || abort "Module template dir not found"
                zip -"$COMPRESSION_LEVEL" -FSqr "${CWD}/${BUILD_DIR}/${module_output}" .
                popd >/dev/null || :
                pr "Built ${table} (root): '${BUILD_DIR}/${module_output}'"
        done

        if [ "$build_success" = true ]; then
                local patches_ver_clean shim_ver_clean
                patches_ver_clean=$(extract_patches_version "${args[ptjar]}")
                shim_ver_clean="${args[shim_ver]-}"
                echo "${table}|${version}|${app_name}|${args[rv_brand]}|${args[patches_src]:-unknown}|${patches_ver_clean}|${mode_arg}|${arch_f}|${shim_ver_clean}" >> "$TEMP_DIR/build_success.log"
        else
                echo "${table}|FAILED|Patching failed" >> "$TEMP_DIR/build_failed.log"
        fi
}

list_args() { tr -d '\t\r' <<<"$1" | tr -s ' ' | sed 's/" "/"\n"/g' | sed 's/\([^"]\)"\([^"]\)/\1'\''\2/g' | grep -v '^$' || :; }
join_args() { list_args "$1" | sed "s/^/${2} /" | paste -sd " " - || :; }

module_config() {
        echo "PKG_NAME=$2
PKG_VER=$3
MODULE_ARCH=arm64" >"$1/config"
}
module_prop() {
        local build_date
        build_date=$(date -u +%Y-%m-%d)
        echo "id=${1}
name=${2}
version=v${3}
versionCode=${NEXT_VER_CODE}
author=Drsexo (Github)
description=${4} | ${build_date}
banner=banner.jpg" >"${6}/module.prop"
        if [ "$ENABLE_MODULE_UPDATE" = true ]; then echo "updateJson=${5}" >>"${6}/module.prop"; fi
}