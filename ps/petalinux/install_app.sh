#!/usr/bin/env bash
# Usage: bash petalinux/install_app.sh /path/to/petalinux/project
set -euo pipefail
package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_dir="${1:?Usage: bash petalinux/install_app.sh /path/to/petalinux/project}"
if [[ ! -f "$project_dir/project-spec/configs/rootfs_config" ]]; then
    echo "Not a PetaLinux project: $project_dir" >&2
    exit 1
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
config_file="$project_dir/project-spec/configs/rootfs_config"
grep -qxF 'CONFIG_pose-cnn-rx5=y' "$config_file" || printf '\nCONFIG_pose-cnn-rx5=y\n' >> "$config_file"
echo "Application installed: $recipe_dir"
echo "Merge petalinux/system-user.dtsi with your project Device Tree separately."
echo "Next: petalinux-build -c pose-cnn-rx5 -x clean"
echo "      petalinux-build -c pose-cnn-rx5"
echo "      petalinux-build"
