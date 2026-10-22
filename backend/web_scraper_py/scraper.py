#!/usr/bin/env python3
"""
Simple web scraper.

Fetches a page, extracts its title and all links (resolved to absolute URLs),
and saves them to a CSV file.

Usage:
    python scraper.py <url> [output.csv]
"""

import csv
import sys
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup

HEADERS = {
    "User-Agent": "Mozilla/5.0 (compatible; SimpleScraper/1.0)"
}


def fetch_html(url: str, timeout: int = 10) -> str:
    response = requests.get(url, headers=HEADERS, timeout=timeout)
    response.raise_for_status()
    return response.text


def extract_links(html: str, base_url: str) -> list[tuple[str, str]]:
    soup = BeautifulSoup(html, "lxml")
    results = []

    for a_tag in soup.find_all("a", href=True):
        href = a_tag["href"].strip()
        text = a_tag.get_text(strip=True)

        if not href or href.startswith("#") or href.startswith("javascript:"):
            continue

        absolute_url = urljoin(base_url, href)

        # Only keep http/https links
        if urlparse(absolute_url).scheme in ("http", "https"):
            results.append((text, absolute_url))

    return results


def save_to_csv(rows: list[tuple[str, str]], output_path: str) -> None:
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["Text", "Url"])
        writer.writerows(rows)


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python scraper.py <url> [output.csv]")
        sys.exit(1)

    url = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else "links.csv"

    print(f"Fetching: {url}")
    try:
        html = fetch_html(url)
    except requests.RequestException as e:
        print(f"Failed to fetch page: {e}")
        sys.exit(1)

    soup = BeautifulSoup(html, "lxml")
    title = soup.title.string.strip() if soup.title and soup.title.string else "(no title)"
    print(f"Title: {title}")

    links = extract_links(html, url)
    print(f"Found {len(links)} links.")

    save_to_csv(links, output_path)
    print(f"Saved results to {output_path}")


if __name__ == "__main__":
    main()
