"""
A simple web scraper using requests and BeautifulSoup.
Demonstrates best practices for respectful web scraping.
"""

import requests
from bs4 import BeautifulSoup
import time
from urllib.parse import urljoin
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class WebScraper:
    def __init__(self, base_url, headers=None, delay=1):
        """
        Initialize the web scraper.
        
        Args:
            base_url (str): The starting URL to scrape
            headers (dict): Optional custom headers
            delay (int): Delay between requests in seconds (be respectful!)
        """
        self.base_url = base_url
        self.delay = delay
        self.session = requests.Session()
        
        # Set a user agent to identify your scraper
        default_headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }
        
        if headers:
            default_headers.update(headers)
        
        self.session.headers.update(default_headers)
    
    def fetch_page(self, url):
        """
        Fetch a single page and return parsed HTML.
        
        Args:
            url (str): The URL to fetch
            
        Returns:
            BeautifulSoup: Parsed HTML content or None if failed
        """
        try:
            logger.info(f"Fetching: {url}")
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            
            # Be respectful - add delay between requests
            time.sleep(self.delay)
            
            return BeautifulSoup(response.content, 'html.parser')
        
        except requests.RequestException as e:
            logger.error(f"Error fetching {url}: {e}")
            return None
    
    def scrape_links(self, url, selector='a'):
        """
        Scrape all links from a page.
        
        Args:
            url (str): The URL to scrape
            selector (str): CSS selector for links (default: all <a> tags)
            
        Returns:
            list: List of absolute URLs found
        """
        soup = self.fetch_page(url)
        if not soup:
            return []
        
        links = []
        for link in soup.select(selector):
            href = link.get('href')
            if href:
                # Convert relative URLs to absolute
                absolute_url = urljoin(url, href)
                links.append(absolute_url)
        
        logger.info(f"Found {len(links)} links")
        return links
    
    def scrape_data(self, url, selectors):
        """
        Scrape specific data from a page using CSS selectors.
        
        Args:
            url (str): The URL to scrape
            selectors (dict): Dictionary mapping data names to CSS selectors
                             e.g., {'title': 'h1', 'price': '.price'}
            
        Returns:
            dict: Extracted data
        """
        soup = self.fetch_page(url)
        if not soup:
            return {}
        
        data = {'url': url}
        
        for name, selector in selectors.items():
            elements = soup.select(selector)
            if elements:
                # Return list if multiple elements, single if one
                data[name] = [el.get_text(strip=True) for el in elements]
                if len(data[name]) == 1:
                    data[name] = data[name][0]
            else:
                data[name] = None
        
        return data
    
    def close(self):
        """Close the session."""
        self.session.close()


# Example usage
if __name__ == "__main__":
    # Example 1: Scrape links from a website
    scraper = WebScraper('https://example.com', delay=2)
    
    print("=== Example 1: Scraping Links ===")
    links = scraper.scrape_links('https://example.com')
    for link in links[:5]:  # Print first 5 links
        print(link)
    
    print("\n=== Example 2: Scraping Specific Data ===")
    # Example 2: Scrape specific data
    selectors = {
        'title': 'h1',
        'paragraphs': 'p',
        'links': 'a'
    }
    
    data = scraper.scrape_data('https://example.com', selectors)
    print(f"Title: {data.get('title')}")
    print(f"First paragraph: {data.get('paragraphs')}")
    
    scraper.close()
