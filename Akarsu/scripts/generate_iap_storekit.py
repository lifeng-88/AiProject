#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从后台套餐接口或导出的 JSON 生成 Xcode StoreKit 配置文件（Consumable IAP）。

用法示例：
  # 1) 使用已保存的接口响应（推荐：在 App/Charles 中复制 GET /v1/packages 的 JSON 存为 packages.json）
  python3 scripts/generate_iap_storekit.py -i packages.json -o bbb/Config/IAP.storekit

  # 2) 直接请求（需 Bearer；channel_id 默认与 AppConfig.getChannel() 一致 IOS10052）
  export API_TOKEN='你的 access_token'
  python3 scripts/generate_iap_storekit.py --api-url https://api.example.com --token "$API_TOKEN"

仅会为同时包含 appleProductId / apple_product_id 的套餐生成商品；无则报错退出。
"""

from __future__ import annotations

import argparse
import json
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


def _cents_to_display(cents: int) -> str:
    return f"{cents / 100.0:.2f}"


def _parse_price(val: Any) -> int:
    if val is None:
        return 0
    if isinstance(val, int):
        return val
    if isinstance(val, float):
        return int(val)
    s = str(val).strip()
    if not s:
        return 0
    try:
        return int(s)
    except ValueError:
        try:
            return int(float(s))
        except ValueError:
            return 0


def _apple_id(pkg: dict[str, Any]) -> str | None:
    v = pkg.get("appleProductId") or pkg.get("apple_product_id")
    if v is None:
        return None
    s = str(v).strip()
    return s if s else None


def _normalize_list(data: Any) -> list[dict[str, Any]]:
    if isinstance(data, list):
        return [x for x in data if isinstance(x, dict)]
    if not isinstance(data, dict):
        return []
    if "list" in data and isinstance(data["list"], list):
        return [x for x in data["list"] if isinstance(x, dict)]
    if "data" in data:
        inner = data["data"]
        if isinstance(inner, list):
            return [x for x in inner if isinstance(x, dict)]
        if isinstance(inner, dict) and isinstance(inner.get("list"), list):
            return [x for x in inner["list"] if isinstance(x, dict)]
    return []


def _package_to_product(pkg: dict[str, Any]) -> dict[str, Any] | None:
    aid = _apple_id(pkg)
    if not aid:
        return None
    pid = pkg.get("packageId") if pkg.get("packageId") is not None else pkg.get("id")
    name = str(pkg.get("name") or f"Package {pid}")
    dp = _parse_price(pkg.get("discountPrice"))
    display_price = _cents_to_display(dp)
    gold = pkg.get("gold")
    bonus = pkg.get("bonus")
    internal = f"PKG_{pid}_{aid}"
    internal = "".join(c if c.isalnum() or c in "_-" else "_" for c in internal)[:80]
    return {
        "displayPrice": display_price,
        "familyShareable": False,
        "internalID": internal,
        "localizations": [
            {
                "description": f"{name} — {gold}+{bonus} coins (channel package)",
                "displayName": name[:40],
                "locale": "en_US",
            }
        ],
        "productID": aid,
        "referenceName": name[:64],
        "type": "Consumable",
    }


def _fetch_packages(base_url: str, channel_id: str, token: str | None) -> dict[str, Any]:
    base = base_url.rstrip("/")
    url = f"{base}/v1/packages?channel_id={urllib.parse.quote(str(channel_id), safe='')}"
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(req, timeout=60, context=ctx) as resp:
        body = resp.read().decode("utf-8")
        return json.loads(body)


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate IAP.storekit from /v1/packages or JSON export")
    ap.add_argument("-i", "--input", help="JSON file: full API body or {list:[packages...]}")
    ap.add_argument("--api-url", help="API base URL (e.g. https://api.glamai01.it.com)")
    ap.add_argument("--token", help="Bearer token (optional if server allows anonymous)")
    ap.add_argument("--channel", default="IOS10052", help="channel_id query param (default IOS10052)")
    ap.add_argument("-o", "--output", default="bbb/Config/IAP.storekit", help="Output .storekit path")
    args = ap.parse_args()

    if args.input:
        with open(args.input, encoding="utf-8") as f:
            data = json.load(f)
    elif args.api_url:
        try:
            data = _fetch_packages(args.api_url, args.channel, args.token)
        except urllib.error.HTTPError as e:
            print(f"HTTP {e.code}: {e.reason}. 若需鉴权请传入 --token。", file=sys.stderr)
            sys.exit(1)
        except OSError as e:
            print(f"请求失败: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        print("请指定 -i/--input JSON 文件，或 --api-url（可加 --token）", file=sys.stderr)
        sys.exit(2)

    raw_list = _normalize_list(data)
    products = []
    skipped = 0
    for pkg in raw_list:
        p = _package_to_product(pkg)
        if p:
            products.append(p)
        else:
            skipped += 1

    if not products:
        print(
            "错误: 没有带 appleProductId / apple_product_id 的套餐，无法生成 IAP.storekit。\n"
            f"已解析 {len(raw_list)} 条套餐，跳过 {skipped} 条无商品 ID。",
            file=sys.stderr,
        )
        sys.exit(1)

    out = {
        "appPolicies": {
            "eula": "",
            "policies": [{"locale": "en_US", "policyText": "", "policyURL": ""}],
        },
        "identifier": "BBB_IAP_FROM_API",
        "nonRenewingSubscriptions": [],
        "products": products,
        "settings": {
            "_failTransactionsEnabled": False,
            "_locale": "en_US",
            "_storefront": "USA",
            "_storeKitErrors": [],
        },
        "subscriptionGroups": [],
        "version": {"major": 3, "minor": 0},
    }

    out_path = args.output
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"已写入 {out_path}（{len(products)} 个消耗型商品，跳过无 apple 商品 ID 的 {skipped} 条）")


if __name__ == "__main__":
    main()
