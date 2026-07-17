#!/usr/bin/env bash

set -uo pipefail
shopt -s nullglob

source utils.sh

trap "abort" INT

if [ "${1-}" = "clean" ]; then
        rm -rf "$TEMP_DIR" "$BUILD_DIR" build.md
        exit 0
fi

jq --version >/dev/null || abort "\`jq\` is not installed. install it with 'apt install jq' or equivalent"
java --version >/dev/null || abort "\`openjdk 21\` is not installed. install it with 'apt install openjdk-21-jre' or equivalent"
zip --version >/dev/null || abort "\`zip\` is not installed. install it with 'apt install zip' or equivalent"

set_prebuilts

vtf() { if ! isoneof "${1}" "true" "false"; then abort "ERROR: '${1}' is not a valid option for '${2}': only true or false is allowed"; fi; }

toml_prep "${1:-config.toml}" || abort "could not find config file '${1:-config.toml}'\n\tUsage: $0 <config.toml>"
main_config_t=$(toml_get_table_main)
COMPRESSION_LEVEL=$(toml_get "$main_config_t" compression-level) || COMPRESSION_LEVEL="9"
if ! PARALLEL_JOBS=$(toml_get "$main_config_t" parallel-jobs); then
        PARALLEL_JOBS=$(nproc)
fi
DEF_PATCHES_VER=$(toml_get "$main_config_t" patches-version) || DEF_PATCHES_VER="latest"
DEF_CLI_VER=$(toml_get "$main_config_t" cli-version) || DEF_CLI_VER="latest"
DEF_PATCHES_SRC=$(toml_get "$main_config_t" patches-source) || DEF_PATCHES_SRC="MorpheApp/morphe-patches"
DEF_CLI_SRC=$(toml_get "$main_config_t" cli-source) || DEF_CLI_SRC="MorpheApp/morphe-desktop"
DEF_RV_BRAND=$(toml_get "$main_config_t" brand) || DEF_RV_BRAND=$(toml_get "$main_config_t" rv-brand) || DEF_RV_BRAND="Morphe"
DEF_RIPLIB=$(toml_get "$main_config_t" riplib) || DEF_RIPLIB="true"
mkdir -p "$TEMP_DIR" "$BUILD_DIR"

BUILD_FILTER="${BUILD_FILTER:-all}"
BUILD_FILTER="${BUILD_FILTER,,}"

pr "Build filter: $BUILD_FILTER"

should_build() {
        local table_lower="${1,,}" brand_lower="$2"
        [ "$BUILD_FILTER" = all ] && return 0
        local IFS=','
        for f in $BUILD_FILTER; do
                f="${f// /}"
                [ -z "$f" ] && continue
                if [ "$table_lower" = "$f" ] || [[ "$brand_lower" == *"$f"* ]]; then
                        return 0
                fi
        done
        return 1
}

: > "$TEMP_DIR/build_success.log"
: > "$TEMP_DIR/build_failed.log"
: > "$TEMP_DIR/patches_sources.log"
: > "$TEMP_DIR/app_order.log"

: >build.md
ENABLE_MODULE_UPDATE=$(toml_get "$main_config_t" enable-module-update) || ENABLE_MODULE_UPDATE=true
if [ "$ENABLE_MODULE_UPDATE" = true ] && [ -z "${GITHUB_REPOSITORY-}" ]; then
        pr "You are building locally. Module updates will not be enabled."
        ENABLE_MODULE_UPDATE=false
fi
if ((COMPRESSION_LEVEL > 9)) || ((COMPRESSION_LEVEL < 0)); then abort "compression-level must be within 0-9"; fi

rm -rf module/bin/*/tmp.*
for file in "$TEMP_DIR"/*/changelog.md; do
        [ -f "$file" ] && : >"$file"
done

mkdir -p ${MODULE_TEMPLATE_DIR}/bin/arm64 ${MODULE_TEMPLATE_DIR}/bin/arm ${MODULE_TEMPLATE_DIR}/bin/x86 ${MODULE_TEMPLATE_DIR}/bin/x64

idx=0
for table_name in $(toml_get_table_names); do
        if [ -z "$table_name" ]; then continue; fi
        t=$(toml_get_table "$table_name")
        enabled=$(toml_get "$t" enabled) || enabled=true
        vtf "$enabled" "enabled"
        if [ "$enabled" = false ]; then continue; fi

        local_rv_brand=$(toml_get "$t" brand) || local_rv_brand=$(toml_get "$t" rv-brand) || local_rv_brand=$DEF_RV_BRAND
        brand_lower="${local_rv_brand,,}"

        if ! should_build "$table_name" "$brand_lower"; then
                pr "Skipping ${table_name} (not in build filter)"
                continue
        fi

        echo "$table_name" >> "$TEMP_DIR/app_order.log"

        if ((idx >= PARALLEL_JOBS)); then
                wait -n || true
                idx=$((idx - 1))
        fi

        declare -A app_args
        patches_src=$(toml_get "$t" patches-source) || patches_src=$DEF_PATCHES_SRC
        patches_ver=$(toml_get "$t" patches-version) || patches_ver=$DEF_PATCHES_VER
        cli_src=$(toml_get "$t" cli-source) || cli_src=$DEF_CLI_SRC
        cli_ver=$(toml_get "$t" cli-version) || cli_ver=$DEF_CLI_VER

        echo "$patches_src" >> "$TEMP_DIR/patches_sources.log"

        if ! PREBUILTS="$(get_prebuilts "$cli_src" "$cli_ver" "$patches_src" "$patches_ver")"; then
                echo "${table_name}|FAILED|Could not download prebuilts" >> "$TEMP_DIR/build_failed.log"
                continue
        fi
        read -r patches_jar cli_jar <<<"$PREBUILTS"
        app_args[cli]=$cli_jar
        app_args[ptjar]=$patches_jar
        app_args[patches_src]=$patches_src

        app_args[riplib]=$(toml_get "$t" riplib) || app_args[riplib]=$DEF_RIPLIB
        app_args[cli_supports_striplibs]=$(check_striplibs "$cli_jar")

        app_args[rv_brand]=$local_rv_brand
        app_args[excluded_patches]=$(toml_get "$t" excluded-patches) || app_args[excluded_patches]=""
        if [ -n "${app_args[excluded_patches]}" ] && [[ ${app_args[excluded_patches]} != *'"'* ]]; then abort "patch names inside excluded-patches must be quoted"; fi
        app_args[included_patches]=$(toml_get "$t" included-patches) || app_args[included_patches]=""
        if [ -n "${app_args[included_patches]}" ] && [[ ${app_args[included_patches]} != *'"'* ]]; then abort "patch names inside included-patches must be quoted"; fi
        app_args[exclusive_patches]=$(toml_get "$t" exclusive-patches) && vtf "${app_args[exclusive_patches]}" "exclusive-patches" || app_args[exclusive_patches]=false
        app_args[version]=$(toml_get "$t" version) || app_args[version]="auto"
        app_args[app_name]=$(toml_get "$t" app-name) || app_args[app_name]=$table_name

        app_args[shim_jar]=""
        app_args[shim_ver]=""
        if [ "${app_args[app_name],,}" = "x" ]; then
                shim_result=""
                if ! shim_result="$(get_gitlab_prebuilts "inotia00/x-shim" "latest")"; then
                        echo "${table_name}|FAILED|Could not download shim prebuilts" >> "$TEMP_DIR/build_failed.log"
                        continue
                fi
                app_args[shim_jar]=$(awk '{print $1}' <<<"$shim_result")
                app_args[shim_ver]=$(awk '{print $2}' <<<"$shim_result")
        fi
        app_args[patcher_args]=$(toml_get "$t" patcher-args) || app_args[patcher_args]=""
        app_args[table]=$table_name
        app_args[build_mode]=$(toml_get "$t" build-mode) && {
                if ! isoneof "${app_args[build_mode]}" both apk module; then
                        abort "ERROR: build-mode '${app_args[build_mode]}' is not a valid option for '${table_name}': only 'both', 'apk' or 'module' is allowed"
                fi
        } || app_args[build_mode]=apk
        app_args[include_stock]=$(toml_get "$t" include-stock) && {
                if ! isoneof "${app_args[include_stock]}" disable merged split; then
                        abort "ERROR: include-stock '${app_args[include_stock]}' is not a valid option for '${table_name}': only 'disable', 'merged' or 'split' is allowed"
                fi
        } || app_args[include_stock]=merged

        unset 'app_args[dl_from]'
        for dl_from in "${DL_SRCS[@]}"; do
                if app_args[${dl_from}_dlurl]=$(toml_get "$t" "${dl_from}-dlurl"); then
                        app_args[${dl_from}_dlurl]=${app_args[${dl_from}_dlurl]%/}
                        app_args[${dl_from}_dlurl]=${app_args[${dl_from}_dlurl]%download}
                        app_args[${dl_from}_dlurl]=${app_args[${dl_from}_dlurl]%/}
                        app_args[dl_from]=${dl_from}
                else
                        app_args[${dl_from}_dlurl]=""
                fi
        done
        if [ -z "${app_args[dl_from]-}" ]; then abort "ERROR: no 'dlurl' option was set for '$table_name'. (${DL_SRCS[*]})"; fi

        app_args[pkg_name]=$(toml_get "$t" pkg-name) || app_args[pkg_name]=""
        app_args[dpi]=$(toml_get "$t" dpi) || app_args[dpi]=""
        table_name_f=${table_name,,}
        table_name_f=${table_name_f// /-}
        app_args[module_prop_name]=$(toml_get "$t" module-prop-name) || app_args[module_prop_name]="${table_name_f}"

        idx=$((idx + 1))
        build_rv "$(declare -p app_args)" &
done
wait || true
_clean_tmp

BUILD_DATE=$(date -u +%Y-%m-%d)
REPO_URL="https://github.com/${GITHUB_REPOSITORY:-Drsexo/Morphe-Obtainium}"

mkdir -p "$TEMP_DIR/release_notes"

while IFS='|' read -r table_name version app_name brand patches_src patches_ver build_mode arch_f shim_ver; do
        [ -z "$table_name" ] && continue

        local_app_tag="${app_name,,}"
        local_app_tag="${local_app_tag// /-}"
        local_brand_tag="${brand,,}"
        local_brand_tag="${local_brand_tag// /-}"
        release_tag_base="${local_app_tag}-${local_brand_tag}"

        version_f=${version// /}
        version_f=${version_f#v}
        release_tag="${release_tag_base}-v${version_f}"

        patches_display="${patches_ver}"

        brand_lower="${brand,,}"
        cli_name=""
        patches_changelog=""
        cli_changelog=""
        if [[ "$brand_lower" == *"morphe"* ]] || [[ "$brand_lower" == *"piko"* ]]; then
                cli_name="Morphe CLI"
                if [[ "$brand_lower" == *"piko"* ]]; then
                        patches_changelog="[Patches](https://github.com/crimera/piko/releases)"
                else
                        patches_changelog="[Patches](https://github.com/MorpheApp/morphe-patches/releases)"
                fi
                cli_changelog="[CLI](https://github.com/MorpheApp/morphe-desktop/releases)"
        else
                cli_name="ReVanced CLI"
                patches_changelog="[Patches](https://github.com/ReVanced/revanced-patches/releases)"
                cli_changelog="[CLI](https://github.com/inotia00/revanced-cli/releases)"
        fi

        cli_ver_display=""
        for cli_file in "$TEMP_DIR"/*/morphe-cli-*.jar "$TEMP_DIR"/*/morphe-desktop-*.jar "$TEMP_DIR"/*/revanced-cli-*.jar; do
                if [ -f "$cli_file" ]; then
                        cli_ver_display=$(extract_cli_version "$cli_file")
                        break
                fi
        done

        shim_display=""
        shim_changelog=""
        app_name_lower_chk="${app_name,,}"
        if [ "$app_name_lower_chk" = "x" ] && [ -n "${shim_ver-}" ]; then
                shim_display="$shim_ver"
                shim_changelog="[Shim](https://gitlab.com/inotia00/x-shim/-/releases)"
        fi

        app_icon=""
        raw_base="https://raw.githubusercontent.com/${GITHUB_REPOSITORY:-Drsexo/Morphe-Obtainium}/main/docs"
        case "${app_name,,}" in
                "youtube") app_icon="${raw_base}/youtube.png" ;;
                "youtube music") app_icon="${raw_base}/music.png" ;;
                "reddit") app_icon="${raw_base}/reddit.png" ;;
                "x") app_icon="${raw_base}/x.png" ;;
                "instagram") app_icon="${raw_base}/instagram.png" ;;
        esac

        needs_microg=false
        app_name_lower="${app_name,,}"
        if [[ "$app_name_lower" == "youtube" ]] || [[ "$app_name_lower" == "youtube music" ]]; then
                needs_microg=true
        fi

        {
                echo "<div align=\"center\">"
                echo ""
                if [ -n "$app_icon" ]; then
                        echo "<img src=\"${app_icon}\" width=\"100\" height=\"100\">"
                        echo ""
                fi
                echo "### **${version}**"
                echo ""
                echo "</div>"
                echo ""
                echo "**Patches** \`${patches_display}\`  "
                if [ -n "$cli_ver_display" ]; then
                        echo "**${cli_name}** \`${cli_ver_display}\`  "
                fi
                if [ -n "$shim_display" ]; then
                        echo "**Shim** \`${shim_display}\`  "
                fi
                echo "**Date** \`${BUILD_DATE}\`  "
                echo ""
                if [ -n "$shim_changelog" ]; then
                        echo "📋 Changelogs: ${patches_changelog} · ${cli_changelog} · ${shim_changelog}"
                else
                        echo "📋 Changelogs: ${patches_changelog} · ${cli_changelog}"
                fi
                if [ "$needs_microg" = true ]; then
                        echo ""
                        echo "<sub>"
                        echo ""
                        echo "⚠️ **Non-root:** Install [MicroG-RE](https://github.com/MorpheApp/MicroG-RE/releases) for Google login"
                        echo ""
                        echo "🔧 **Root:** Use [zygisk-detach](https://github.com/j-hc/zygisk-detach) to detach from Play Store"
                        echo ""
                        echo "</sub>"
                fi
        } > "$TEMP_DIR/release_notes/${release_tag_base}.md"

        echo "${release_tag}|${release_tag_base}|${app_name} ${brand}|${local_app_tag}-${local_brand_tag}" >> "$TEMP_DIR/release_tags.log"

done < "$TEMP_DIR/build_success.log"

if [ -f "$TEMP_DIR/build_success.log" ]; then
        while IFS='|' read -r _t _v _a brand patches_src patches_ver _bm _af _sv; do
                [ -z "$patches_src" ] && continue
                src_key="${patches_src##*/}"
                src_key="${src_key,,}"
                echo "$patches_ver" > "$TEMP_DIR/last-patches-${src_key}.txt"
        done < "$TEMP_DIR/build_success.log"
fi

{
        echo "# Build ${BUILD_DATE}"
        echo ""
        while IFS= read -r app_name; do
                if grep -q "^${app_name}|" "$TEMP_DIR/build_success.log" 2>/dev/null; then
                        version=$(grep "^${app_name}|" "$TEMP_DIR/build_success.log" | head -1 | cut -d'|' -f2)
                        echo "${app_name} \`${version}\` ✅  "
                elif grep -q "^${app_name}|" "$TEMP_DIR/build_failed.log" 2>/dev/null; then
                        echo "${app_name} — ❌  "
                fi
        done < "$TEMP_DIR/app_order.log"
        echo ""
} > build.md

if [ -z "$(ls -A1 "${BUILD_DIR}" 2>/dev/null)" ]; then
        pr "No apps were built."
fi

pr "Done"