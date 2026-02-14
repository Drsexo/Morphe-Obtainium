#!/usr/bin/env bash

set -uo pipefail
shopt -s nullglob
trap "rm -rf temp/*tmp.* temp/*/*tmp.* temp/*-temporary-files; exit 130" INT

if [ "${1-}" = "clean" ]; then
	rm -rf temp build logs build.md
	exit 0
fi

source utils.sh

jq --version >/dev/null || abort "\`jq\` is not installed. install it with 'apt install jq' or equivalent"
java --version >/dev/null || abort "\`openjdk 17\` is not installed. install it with 'apt install openjdk-17-jre' or equivalent"
zip --version >/dev/null || abort "\`zip\` is not installed. install it with 'apt install zip' or equivalent"

set_prebuilts

vtf() { if ! isoneof "${1}" "true" "false"; then abort "ERROR: '${1}' is not a valid option for '${2}': only true or false is allowed"; fi; }

toml_prep "${1:-config.toml}" || abort "could not find config file '${1:-config.toml}'\n\tUsage: $0 <config.toml>"
main_config_t=$(toml_get_table_main)
COMPRESSION_LEVEL=$(toml_get "$main_config_t" compression-level) || COMPRESSION_LEVEL="9"
if ! PARALLEL_JOBS=$(toml_get "$main_config_t" parallel-jobs); then
	if [ "$OS" = Android ]; then PARALLEL_JOBS=1; else PARALLEL_JOBS=$(nproc); fi
fi
DEF_PATCHES_VER=$(toml_get "$main_config_t" patches-version) || DEF_PATCHES_VER="latest"
DEF_CLI_VER=$(toml_get "$main_config_t" cli-version) || DEF_CLI_VER="latest"
DEF_PATCHES_SRC=$(toml_get "$main_config_t" patches-source) || DEF_PATCHES_SRC="MorpheApp/morphe-patches"
DEF_CLI_SRC=$(toml_get "$main_config_t" cli-source) || DEF_CLI_SRC="MorpheApp/morphe-cli"
DEF_RV_BRAND=$(toml_get "$main_config_t" brand) || DEF_RV_BRAND=$(toml_get "$main_config_t" rv-brand) || DEF_RV_BRAND="Morphe"
DEF_DPI_LIST=$(toml_get "$main_config_t" dpi) || DEF_DPI_LIST="nodpi anydpi"
DEF_ARCH=$(toml_get "$main_config_t" arch) || DEF_ARCH="all"
DEF_RIPLIB=$(toml_get "$main_config_t" riplib) || DEF_RIPLIB="true"
mkdir -p "$TEMP_DIR" "$BUILD_DIR"

BUILD_MORPHE="${BUILD_MORPHE:-true}"
BUILD_REVANCED="${BUILD_REVANCED:-true}"
BUILD_PIKO="${BUILD_PIKO:-true}"

pr "Build configuration: Morphe=$BUILD_MORPHE, ReVanced=$BUILD_REVANCED, Piko=$BUILD_PIKO"

: > "$TEMP_DIR/build_success.log"
: > "$TEMP_DIR/build_failed.log"
: > "$TEMP_DIR/patches_sources.log"
: > "$TEMP_DIR/app_order.log"

: >build.md
ENABLE_MAGISK_UPDATE=$(toml_get "$main_config_t" enable-magisk-update) || ENABLE_MAGISK_UPDATE=true
if [ "$ENABLE_MAGISK_UPDATE" = true ] && [ -z "${GITHUB_REPOSITORY-}" ]; then
	pr "You are building locally. Magisk updates will not be enabled."
	ENABLE_MAGISK_UPDATE=false
fi
if ((COMPRESSION_LEVEL > 9)) || ((COMPRESSION_LEVEL < 0)); then abort "compression-level must be within 0-9"; fi

rm -rf module-template/bin/*/tmp.*
for file in "$TEMP_DIR"/*/changelog.md; do
	[ -f "$file" ] && : > "$file"
done

mkdir -p ${MODULE_TEMPLATE_DIR}/bin/arm64 ${MODULE_TEMPLATE_DIR}/bin/arm ${MODULE_TEMPLATE_DIR}/bin/x86 ${MODULE_TEMPLATE_DIR}/bin/x64
gh_dl "${MODULE_TEMPLATE_DIR}/bin/arm64/cmpr" "https://github.com/j-hc/cmpr/releases/latest/download/cmpr-arm64-v8a"
gh_dl "${MODULE_TEMPLATE_DIR}/bin/arm/cmpr" "https://github.com/j-hc/cmpr/releases/latest/download/cmpr-armeabi-v7a"
gh_dl "${MODULE_TEMPLATE_DIR}/bin/x86/cmpr" "https://github.com/j-hc/cmpr/releases/latest/download/cmpr-x86"
gh_dl "${MODULE_TEMPLATE_DIR}/bin/x64/cmpr" "https://github.com/j-hc/cmpr/releases/latest/download/cmpr-x86_64"


idx=0
for table_name in $(toml_get_table_names); do
	if [ -z "$table_name" ]; then continue; fi
	t=$(toml_get_table "$table_name")
	enabled=$(toml_get "$t" enabled) || enabled=true
	vtf "$enabled" "enabled"
	if [ "$enabled" = false ]; then continue; fi

	local_rv_brand=$(toml_get "$t" brand) || local_rv_brand=$(toml_get "$t" rv-brand) || local_rv_brand=$DEF_RV_BRAND
	brand_lower="${local_rv_brand,,}"

	if [[ "$brand_lower" == *"morphe"* ]] && [ "$BUILD_MORPHE" != "true" ]; then
		pr "Skipping ${table_name} (no Morphe patches update)"
		continue
	fi
	if [[ "$brand_lower" == *"revanced"* ]] && [ "$BUILD_REVANCED" != "true" ]; then
		pr "Skipping ${table_name} (no ReVanced patches update)"
		continue
	fi
	if [[ "$brand_lower" == *"piko"* ]] && [ "$BUILD_PIKO" != "true" ]; then
		pr "Skipping ${table_name} (no Piko patches update)"
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
	read -r cli_jar patches_jar <<<"$PREBUILTS"
	app_args[cli]=$cli_jar
	app_args[ptjar]=$patches_jar
	app_args[patches_src]=$patches_src

	app_args[riplib]=false

	local_riplib=$(toml_get "$t" riplib) || local_riplib=$DEF_RIPLIB
	if [ "$local_riplib" = "false" ]; then
		app_args[riplib]=false
		app_args[strip_libs]=false
	else
		app_args[strip_libs]=true
	fi

	app_args[rv_brand]=$local_rv_brand
	app_args[excluded_patches]=$(toml_get "$t" excluded-patches) || app_args[excluded_patches]=""
	if [ -n "${app_args[excluded_patches]}" ] && [[ ${app_args[excluded_patches]} != *'"'* ]]; then abort "patch names inside excluded-patches must be quoted"; fi
	app_args[included_patches]=$(toml_get "$t" included-patches) || app_args[included_patches]=""
	if [ -n "${app_args[included_patches]}" ] && [[ ${app_args[included_patches]} != *'"'* ]]; then abort "patch names inside included-patches must be quoted"; fi
	app_args[exclusive_patches]=$(toml_get "$t" exclusive-patches) && vtf "${app_args[exclusive_patches]}" "exclusive-patches" || app_args[exclusive_patches]=false
	app_args[version]=$(toml_get "$t" version) || app_args[version]="auto"
	app_args[app_name]=$(toml_get "$t" app-name) || app_args[app_name]=$table_name
	app_args[patcher_args]=$(toml_get "$t" patcher-args) || app_args[patcher_args]=""
	app_args[table]=$table_name
	app_args[build_mode]=$(toml_get "$t" build-mode) && {
		if ! isoneof "${app_args[build_mode]}" both apk module; then
			abort "ERROR: build-mode '${app_args[build_mode]}' is not a valid option for '${table_name}': only 'both', 'apk' or 'module' is allowed"
		fi
	} || app_args[build_mode]=apk
	app_args[uptodown_dlurl]=$(toml_get "$t" uptodown-dlurl) && {
		app_args[uptodown_dlurl]=${app_args[uptodown_dlurl]%/}
		app_args[uptodown_dlurl]=${app_args[uptodown_dlurl]%download}
		app_args[uptodown_dlurl]=${app_args[uptodown_dlurl]%/}
		app_args[dl_from]=uptodown
	} || app_args[uptodown_dlurl]=""
	app_args[apkmirror_dlurl]=$(toml_get "$t" apkmirror-dlurl) && {
		app_args[apkmirror_dlurl]=${app_args[apkmirror_dlurl]%/}
		app_args[dl_from]=apkmirror
	} || app_args[apkmirror_dlurl]=""
	app_args[archive_dlurl]=$(toml_get "$t" archive-dlurl) && {
		app_args[archive_dlurl]=${app_args[archive_dlurl]%/}
		app_args[dl_from]=archive
	} || app_args[archive_dlurl]=""
	if [ -z "${app_args[dl_from]-}" ]; then abort "ERROR: no 'apkmirror_dlurl', 'uptodown_dlurl' or 'archive_dlurl' option was set for '$table_name'."; fi

	app_args[arch]=$(toml_get "$t" arch) || app_args[arch]="$DEF_ARCH"
	if [ "${app_args[arch]}" != "both" ] && [ "${app_args[arch]}" != "all" ] && [[ ${app_args[arch]} != "arm64-v8a"* ]] && [[ ${app_args[arch]} != "arm-v7a"* ]]; then
		abort "wrong arch '${app_args[arch]}' for '$table_name'"
	fi

	app_args[include_stock]=$(toml_get "$t" include-stock) || app_args[include_stock]=true && vtf "${app_args[include_stock]}" "include-stock"
	app_args[dpi]=$(toml_get "$t" dpi) || app_args[dpi]="$DEF_DPI_LIST"
	table_name_f=${table_name,,}
	table_name_f=${table_name_f// /-}
	app_args[module_prop_name]=$(toml_get "$t" module-prop-name) || app_args[module_prop_name]="${table_name_f}"

	if [ "${app_args[arch]}" = both ]; then
		app_args[table]="$table_name (arm64-v8a)"
		app_args[arch]="arm64-v8a"
		module_prop_name_b=${app_args[module_prop_name]}
		app_args[module_prop_name]="${module_prop_name_b}-arm64"
		idx=$((idx + 1))
		build_rv "$(declare -p app_args)" &
		app_args[table]="$table_name (arm-v7a)"
		app_args[arch]="arm-v7a"
		app_args[module_prop_name]="${module_prop_name_b}-arm"
		if ((idx >= PARALLEL_JOBS)); then
			wait -n || true
			idx=$((idx - 1))
		fi
		idx=$((idx + 1))
		build_rv "$(declare -p app_args)" &
	else
		if [ "${app_args[arch]}" = "arm64-v8a" ]; then
			app_args[module_prop_name]="${app_args[module_prop_name]}-arm64"
		elif [ "${app_args[arch]}" = "arm-v7a" ]; then
			app_args[module_prop_name]="${app_args[module_prop_name]}-arm"
		fi
		idx=$((idx + 1))
		build_rv "$(declare -p app_args)" &
	fi
done
wait || true
rm -rf temp/tmp.*

BUILD_DATE=$(date -u +%Y-%m-%d)
REPO_URL="https://github.com/${GITHUB_REPOSITORY:-Drsexo/Morphe-Obtainium}"

mkdir -p "$TEMP_DIR/release_notes"

while IFS='|' read -r table_name version app_name brand patches_src patches_ver build_mode arch_f; do
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
	patches_display="${patches_display%.rvp}"
	patches_display="${patches_display%.mpp}"

	brand_lower="${brand,,}"
	cli_name=""
	patches_changelog=""
	cli_changelog=""
	if [[ "$brand_lower" == *"morphe"* ]]; then
		cli_name="Morphe CLI"
		patches_changelog="[Patches](https://github.com/MorpheApp/morphe-patches/releases)"
		cli_changelog="[CLI](https://github.com/MorpheApp/morphe-cli/releases)"
	elif [[ "$brand_lower" == *"piko"* ]]; then
		cli_name="ReVanced CLI"
		patches_changelog="[Patches](https://github.com/crimera/piko/releases)"
		cli_changelog="[CLI](https://github.com/inotia00/revanced-cli/releases)"
	else
		cli_name="ReVanced CLI"
		patches_changelog="[Patches](https://github.com/ReVanced/revanced-patches/releases)"
		cli_changelog="[CLI](https://github.com/revanced/revanced-cli/releases)"
	fi

	cli_ver_display=""
	for cli_file in "$TEMP_DIR"/*/morphe-cli-*.jar "$TEMP_DIR"/*/revanced-cli-*.jar; do
		if [ -f "$cli_file" ]; then
			cli_base=$(basename "$cli_file")
			cli_ver_display=$(echo "$cli_base" | sed 's/.*cli-\([0-9.]*\).*/\1/')
			break
		fi
	done

	# Map app name to icon filename
	app_icon=""
	raw_base="https://raw.githubusercontent.com/${GITHUB_REPOSITORY:-Drsexo/Morphe-Obtainium}/main/docs"
	case "${app_name,,}" in
		"youtube") app_icon="${raw_base}/youtube.png" ;;
		"youtube music") app_icon="${raw_base}/music.png" ;;
		"reddit") app_icon="${raw_base}/reddit.png" ;;
		"x") app_icon="${raw_base}/x.png" ;;
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
		echo "**Patches** \`${patches_display}\`"
		if [ -n "$cli_ver_display" ]; then
			echo "**${cli_name}** \`${cli_ver_display}\`"
		fi
		echo "**Date** \`${BUILD_DATE}\`"
		echo ""
		echo "📋 Changelogs: ${patches_changelog} · ${cli_changelog}"
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

{
	echo "# Build ${BUILD_DATE}"
	echo ""
	echo "| App | Version | Status |"
	echo "|-----|---------|--------|"
	while IFS= read -r app_name; do
		if grep -q "^${app_name}|" "$TEMP_DIR/build_success.log" 2>/dev/null; then
			version=$(grep "^${app_name}|" "$TEMP_DIR/build_success.log" | head -1 | cut -d'|' -f2)
			echo "| ${app_name} | \`${version}\` | ✅ |"
		elif grep -q "^${app_name}|" "$TEMP_DIR/build_failed.log" 2>/dev/null; then
			echo "| ${app_name} | — | ❌ |"
		fi
	done < "$TEMP_DIR/app_order.log"
	echo ""
} > build.md

if [ -z "$(ls -A1 "${BUILD_DIR}" 2>/dev/null)" ]; then
	pr "No apps were built."
fi

pr "Done"