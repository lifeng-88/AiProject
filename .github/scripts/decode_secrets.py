#!/usr/bin/env python3
"""Decode GitHub Actions secrets that hold base64 (.p12 / .mobileprovision). Robust to whitespace/BOM/prefixes."""
from __future__ import annotations

import argparse
import base64
import sys


def normalize_b64(raw: str) -> str:
    s = raw.strip().replace("\ufeff", "")
    s = "".join(s.split())
    low = s.lower()
    if "base64," in low:
        s = s.split("base64,", 1)[-1]
        s = "".join(s.split())
    if s.lower().startswith("data:") and "," in s:
        s = s.split(",", 1)[-1]
        s = "".join(s.split())
    return s


def decode_to_file(label: str, raw: str, out_path: str, min_bytes: int) -> None:
    if not raw or not raw.strip():
        print(f"::error::{label}: empty value", file=sys.stderr)
        sys.exit(1)
    s = normalize_b64(raw)
    try:
        binary = base64.b64decode(s, validate=False)
    except Exception as exc:
        print(
            f"::error::{label}: base64 decode failed: {exc}. "
            "Use only the base64 string (no Chinese text, no quotes). "
            "Regenerate: base64 -i file | tr -d '\\n'",
            file=sys.stderr,
        )
        sys.exit(1)
    if len(binary) < min_bytes:
        print(
            f"::error::{label}: decoded only {len(binary)} bytes (too short; truncated or wrong content?)",
            file=sys.stderr,
        )
        sys.exit(1)
    with open(out_path, "wb") as fh:
        fh.write(binary)
    print(f"{label}: wrote {len(binary)} bytes -> {out_path}")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--cert-env", default="CERT_P12_BASE64")
    p.add_argument("--provision-env", default="PROVISION_BASE64")
    p.add_argument("--cert-out", default="/tmp/dist.p12")
    p.add_argument("--provision-out", default="/tmp/app.mobileprovision")
    args = p.parse_args()

    import os

    cert_raw = os.environ.get(args.cert_env, "")
    prov_raw = os.environ.get(args.provision_env, "")

    decode_to_file("APPLE_CERT_P12_BASE64", cert_raw, args.cert_out, min_bytes=32)
    decode_to_file(
        "APPLE_PROVISION_PROFILE_BASE64",
        prov_raw,
        args.provision_out,
        min_bytes=32,
    )


if __name__ == "__main__":
    main()
