#!/usr/bin/env python3
"""
Shopify store scraper using the built-in /products.json endpoint.

Works for any Shopify store (not just Pimoroni), since Shopify exposes
this public JSON API by default: https://<store>/products.json

Usage:
    python shopify_scraper.py <store_url> [output.csv] [--json output.json]

Example:
    python shopify_scraper.py https://shop.pimoroni.com products.csv
"""

import argparse
import csv
import json
import sys
import time
from urllib.parse import urljoin

import requests

HEADERS = {
    "User-Agent": "Mozilla/5.0 (compatible; SimpleScraper/1.0)"
}

PAGE_LIMIT = 250  # Shopify's max page size


def fetch_products_page(base_url: str, page: int, limit: int = PAGE_LIMIT) -> list[dict]:
    url = urljoin(base_url, "/products.json")
    params = {"limit": limit, "page": page}
    resp = requests.get(url, headers=HEADERS, params=params, timeout=15)
    resp.raise_for_status()
    data = resp.json()
    return data.get("products", [])


def fetch_all_products(base_url: str, delay: float = 0.5) -> list[dict]:
    all_products = []
    page = 1

    while True:
        print(f"Fetching page {page}...")
        try:
            products = fetch_products_page(base_url, page)
        except requests.RequestException as e:
            print(f"Request failed on page {page}: {e}")
            break

        if not products:
            break

        all_products.extend(products)
        page += 1
        time.sleep(delay)  # be polite, avoid hammering the store

    return all_products


def flatten_product(product: dict, base_url: str) -> list[dict]:
    """Flatten a Shopify product into one row per variant."""
    rows = []
    handle = product.get("handle", "")
    product_url = urljoin(base_url, f"/products/{handle}")
    image_url = product["images"][0]["src"] if product.get("images") else ""

    variants = product.get("variants") or [{}]
    for variant in variants:
        rows.append({
            "product_id": product.get("id"),
            "title": product.get("title"),
            "vendor": product.get("vendor"),
            "product_type": product.get("product_type"),
            "tags": ", ".join(product.get("tags", [])) if isinstance(product.get("tags"), list) else product.get("tags", ""),
            "variant_title": variant.get("title"),
            "price": variant.get("price"),
            "available": variant.get("available"),
            "sku": variant.get("sku"),
            "url": product_url,
            "image": image_url,
        })

    return rows


def save_csv(rows: list[dict], output_path: str) -> None:
    if not rows:
        print("No rows to save.")
        return

    fieldnames = list(rows[0].keys())
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def save_json(products: list[dict], output_path: str) -> None:
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(products, f, indent=2)


def main() -> None:
    parser = argparse.ArgumentParser(description="Scrape a Shopify store's products.json")
    parser.add_argument("store_url", help="Base URL of the Shopify store, e.g. https://shop.pimoroni.com")
    parser.add_argument("output", nargs="?", default="products.csv", help="Output CSV path")
    parser.add_argument("--json", dest="json_output", help="Also save raw product data as JSON")
    parser.add_argument("--delay", type=float, default=0.5, help="Delay between page requests (seconds)")
    args = parser.parse_args()

    base_url = args.store_url.rstrip("/")

    print(f"Scraping store: {base_url}")
    products = fetch_all_products(base_url, delay=args.delay)
    print(f"Fetched {len(products)} products total.")

    if args.json_output:
        save_json(products, args.json_output)
        print(f"Saved raw product JSON to {args.json_output}")

    rows = []
    for product in products:
        rows.extend(flatten_product(product, base_url))

    save_csv(rows, args.output)
    print(f"Saved {len(rows)} variant rows to {args.output}")


if __name__ == "__main__":
    main()
