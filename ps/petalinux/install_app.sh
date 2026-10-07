#!/usr/bin/env bash
# Usage: bash petalinux/install_app.sh /path/to/petalinux/project [verified_vector_dir]
set -euo pipefail
package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_dir="${1:?Usage: bash petalinux/install_app.sh /path/to/petalinux/project}"
if [[ ! -f "$project_dir/project-spec/configs/rootfs_config" ]]; then
    echo "Not a PetaLinux project: $project_dir" >&2
    exit 1
fi
vector_dir="${2:-}"
if [[ -n "$vector_dir" ]]; then
    for asset in blob_rx5_test.bin input_rx5_test.bin pose_expected.bin; do
        if [[ ! -s "$vector_dir/$asset" ]]; then
            echo "Missing/empty verified vector: $vector_dir/$asset" >&2
            exit 1
        fi
    done
fi
recipe_dir="$project_dir/project-spec/meta-user/recipes-apps/pose-cnn-rx5"
if [[ -e "$recipe_dir" ]]; then
    backup_dir="$project_dir/ps-app-backups/pose-cnn-rx5-$(date +%Y%m%d-%H%M%S)-$$"
    mkdir -p "$backup_dir"
    cp -a "$recipe_dir" "$backup_dir/"
    echo "Existing recipe backup: $backup_dir"
fi
mkdir -p "$recipe_dir/files"
cp "$package_dir/petalinux/pose-cnn-rx5.bb" "$recipe_dir/"
cp "$package_dir/src/"*.c "$recipe_dir/files/"
cp "$package_dir/include/"*.h "$recipe_dir/files/"
cp "$package_dir/test_vectors/"* "$recipe_dir/files/"
printf '# Optional locally supplied, verified board vectors.\n' > "$recipe_dir/pose-cnn-rx5-vectors.inc"
if [[ -n "$vector_dir" ]]; then
    for asset in blob_rx5_test.bin input_rx5_test.bin pose_expected.bin; do
        cp "$vector_dir/$asset" "$recipe_dir/files/"
    done
    printf 'SRC_URI += "file://blob_rx5_test.bin file://input_rx5_test.bin file://pose_expected.bin"\n' >> "$recipe_dir/pose-cnn-rx5-vectors.inc"
else
    echo "Source-only install: supply model/test binaries separately before board execution."
fi
config_file="$project_dir/project-spec/configs/rootfs_config"
grep -qxF 'CONFIG_pose-cnn-rx5=y' "$config_file" || printf '\nCONFIG_pose-cnn-rx5=y\n' >> "$config_file"
echo "Application installed: $recipe_dir"
echo "Merge petalinux/system-user.dtsi with your project Device Tree separately."
echo "Next: petalinux-build -c pose-cnn-rx5 -x clean"
echo "      petalinux-build -c pose-cnn-rx5"
echo "      petalinux-build"
