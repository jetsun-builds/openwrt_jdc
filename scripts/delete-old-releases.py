#!/usr/bin/env python3
"""Delete only the eight release records explicitly requested on 2026-10-11.

Run after the replacement firmware is verified and published. Git tags remain.
The fixed ID/tag allowlist prevents deleting subsequent releases or other repos.
"""
import json
import os
import subprocess

REPOSITORY = "jetsun-builds/openwrt_jdc"
OLD_RELEASES = {
    409156660: "JDCloud-25.12.2-NSS-11",
    409135702: "AX3600-25.12.2-NSS-2",
    408270962: "JDCloud-25.12.2-NSS-9",
    404636529: "JDCloud-25.12.2-NSS-8",
    404551992: "JDCloud-25.12.2-NSS-7",
    404983994: "AX3600-25.12.2-NSS-1",
    403941174: "JDCloud",
    403904443: "IPQ807X",
}


def main():
    if os.environ.get("GITHUB_REPOSITORY") != REPOSITORY:
        raise SystemExit("Release cleanup is restricted to " + REPOSITORY)
    keep_tag = os.environ["KEEP_TAG"]
    if keep_tag in OLD_RELEASES.values():
        raise SystemExit("Refusing to delete the replacement release")
    current = json.loads(subprocess.check_output(
        ["gh", "api", f"repos/{REPOSITORY}/releases/tags/{keep_tag}"], text=True))
    if current["draft"] or not current["assets"]:
        raise SystemExit("Replacement release is not published with assets")
    for release_id, expected_tag in OLD_RELEASES.items():
        endpoint = f"repos/{REPOSITORY}/releases/{release_id}"
        result = subprocess.run(["gh", "api", endpoint], capture_output=True, text=True)
        if result.returncode:
            if "(HTTP 404)" in result.stderr:
                print(f"Already absent: {expected_tag}")
                continue
            raise SystemExit(result.stderr)
        release = json.loads(result.stdout)
        if release["id"] != release_id or release["tag_name"] != expected_tag:
            raise SystemExit(f"Release identity mismatch: {release_id}")
        subprocess.run(["gh", "api", "--method", "DELETE", endpoint], check=True)
        print(f"Deleted release {release_id}: {expected_tag}; Git tag retained")


if __name__ == "__main__":
    main()
