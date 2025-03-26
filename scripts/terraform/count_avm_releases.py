import json
import sys

def count_releases(json_file):
    try:
        with open(json_file, 'r') as f:
            data = json.load(f)
    except Exception as e:
        print(f"Error loading JSON file: {e}")
        return

    PREFIX = "terraform-azurerm-avm-res-"
    long_names = []

    for package in data:
        name = package["name"]
        # Only trim if the name starts with the prefix
        trimmed_name = name[len(PREFIX):] if name.startswith(PREFIX) else name

        # Check if trimmed name is longer than 36 characters
        if len(trimmed_name) > 30:
            long_names.append({
                "original": name,
                "trimmed": trimmed_name,
                "length": len(trimmed_name)
            })
    # Sort by length (longest first)
    long_names = sorted(long_names, key=lambda x: x["length"], reverse=True)

    print(f"\nPackages with names longer than 30 characters (after trimming '{PREFIX}'):")
    print("-" * 80)

    for package in long_names:
        print(f"Original: {package['original']}")
        print(f"Trimmed:  {package['trimmed']}")
        print(f"Length:   {package['length']} characters")
        print("-" * 80)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python count_avm_releases.py <path_to_json_file>")
    else:
        count_releases(sys.argv[1])