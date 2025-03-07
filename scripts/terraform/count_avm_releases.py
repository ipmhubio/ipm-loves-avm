import json
import sys

def count_releases(json_file):
    try:
        with open(json_file, 'r') as f:
            data = json.load(f)
    except Exception as e:
        print(f"Error loading JSON file: {e}")
        return

    packages_with_releases = []
    total_releases = 0

    for package in data:
        name = package["name"]
        release_count = package.get("release_count", 0)

        if release_count > 0:
            packages_with_releases.append({"name": name, "release_count": release_count})
            total_releases += release_count

    # Sort by release count (highest first)
    packages_with_releases = sorted(packages_with_releases, key=lambda x: x["release_count"], reverse=True)

    print(f"Total packages with releases: {len(packages_with_releases)}")
    print(f"Total releases across all packages: {total_releases}")
    print("\nPackage release counts (sorted by most releases):")

    for package in packages_with_releases:
        print(f"{package['name']}: {package['release_count']} releases")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python count_avm_releases.py <path_to_json_file>")
    else:
        count_releases(sys.argv[1])
