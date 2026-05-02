#!/usr/bin/env python3
"""Write Xcode -exportArchive ExportOptions plist for manual signing (CI)."""
from __future__ import annotations

import os
import plistlib
import sys


def main() -> None:
    out_path = os.environ.get("OUT_PATH", "").strip()
    bundle_id = os.environ.get("BUNDLE_ID", "com.Akarsu.net").strip()
    profile_name = os.environ.get("PROFILE_NAME", "").strip()
    team_id = os.environ.get("APPLE_TEAM_ID", "").strip()

    if not out_path:
        print("::error::OUT_PATH is empty", file=sys.stderr)
        sys.exit(1)
    if not profile_name:
        print("::error::PROFILE_NAME is empty (from GITHUB_ENV)", file=sys.stderr)
        sys.exit(1)
    if not team_id:
        print("::error::APPLE_TEAM_ID is empty", file=sys.stderr)
        sys.exit(1)

    data: dict = {
        "method": "app-store-connect",
        "uploadSymbols": True,
        "manageAppVersionAndBuildNumber": False,
        "signingStyle": "manual",
        "teamID": team_id,
        "provisioningProfiles": {bundle_id: profile_name},
    }

    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "wb") as fh:
        plistlib.dump(data, fh)
    print(f"Wrote export options: {out_path} team={team_id} profile={profile_name!r} bundle={bundle_id}")


if __name__ == "__main__":
    main()
