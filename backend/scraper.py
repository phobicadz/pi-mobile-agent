#!/usr/bin/env python3
"""
Simple web scraper example.

Requirements:
    pip install requests beautifulsoup4

Usage:
    python scraper.py <url>

Fetches a web page and extracts the title, all links, and all headings.
"""

import sys
import argparse
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup


def fetch_page(url: str, timeout: int = 10) -> str:
    """Fetch the HTML content of a page."""
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (compatible; SimpleScraper/1.0; "
            "+https://example.com/bot)"
        )
    }
    response = requests.get(url, headers=headers, timeout=timeout)
    response.raise_for_status()
    return response.text


def parse_page(html: str, base_url: str) -> dict:
    """Parse HTML and extract useful data."""
    soup = BeautifulSoup(html, "html.parser")

    title = soup.title.string.strip() if soup.title and soup.title.string else None

    headings = []
    for level in range(1, 7):
        for tag in soup.find_all(f"h{level}"):
            text = tag.get_text(strip=True)
            if text:
                headings.append({"level": level, "text": text})

    links = []
    seen = set()
    for a in soup.find_all("a", href=True):
        href = a["href"].strip()
        if not href or href.startswith("#"):
            continue
        absolute_url = urljoin(base_url, href)
        if absolute_url not in seen:
            seen.add(absolute_url)
            links.append({
                "text": a.get_text(strip=True) or None,
                "url": absolute_url,
            })

    return {
        "title": title,
        "headings": headings,
        "links": links,
    }


def is_valid_url(url: str) -> bool:
    parsed = urlparse(url)
    return bool(parsed.scheme) and bool(parsed.netloc)


def main():
    parser = argparse.ArgumentParser(description="Simple web scraper")
    parser.add_argument("url", help="URL of the page to scrape")
    parser.add_argument(
        "--max-links", type=int, default=None,
        help="Limit the number of links printed"
    )
    args = parser.parse_args()

    if not is_valid_url(args.url):
        print(f"Error: '{args.url}' is not a valid URL", file=sys.stderr)
        sys.exit(1)

    try:
        html = fetch_page(args.url)
    except requests.RequestException as e:
        print(f"Error fetching page: {e}", file=sys.stderr)
        sys.exit(1)

    data = parse_page(html, args.url)

    print(f"Title: {data['title']}\n")

    print(f"Headings ({len(data['headings'])}):")
    for h in data["headings"]:
        print(f"  {'  ' * (h['level'] - 1)}[h{h['level']}] {h['text']}")

    links = data["links"]
    if args.max_links is not None:
        links = links[: args.max_links]

    print(f"\nLinks ({len(data['links'])} total, showing {len(links)}):")
    for link in links:
        text = link["text"] or "(no text)"
        print(f"  - {text} -> {link['url']}")


if __name__ == "__main__":
    main()
