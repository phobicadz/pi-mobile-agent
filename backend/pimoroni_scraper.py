"""
Web scraper tailored for shop.pimoroni.com
Scrapes product information from Pimoroni's electronics shop.
"""

import requests
from bs4 import BeautifulSoup
import time
import json
from urllib.parse import urljoin, urlparse
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class PimoroniScraper:
    def __init__(self, delay=2):
        """
        Initialize the Pimoroni shop scraper.
        
        Args:
            delay (int): Delay between requests in seconds (be respectful!)
        """
        self.base_url = 'https://shop.pimoroni.com'
        self.delay = delay
        self.session = requests.Session()
        
        # Pimoroni-specific user agent
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        })
    
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
            response = self.session.get(url, timeout=15)
            response.raise_for_status()
            
            time.sleep(self.delay)
            return BeautifulSoup(response.content, 'html.parser')
        
        except requests.RequestException as e:
            logger.error(f"Error fetching {url}: {e}")
            return None
    
    def scrape_product(self, product_element):
        """
        Extract product information from a product element.
        
        Args:
            product_element: BeautifulSoup element for a product
            
        Returns:
            dict: Product data (name, price, url, description, etc.)
        """
        try:
            product = {}
            
            # Product name/title
            name_elem = product_element.select_one('h3, h4, .product-title, a.product-name')
            product['name'] = name_elem.get_text(strip=True) if name_elem else None
            
            # Product URL
            link_elem = product_element.select_one('a[href*="/products/"]')
            product['url'] = urljoin(self.base_url, link_elem['href']) if link_elem else None
            
            # Price
            price_elem = product_element.select_one('.price, [class*="price"]')
            product['price'] = price_elem.get_text(strip=True) if price_elem else None
            
            # Description/Snippet
            desc_elem = product_element.select_one('.product-description, .description, p')
            product['description'] = desc_elem.get_text(strip=True) if desc_elem else None
            
            # Image URL
            img_elem = product_element.select_one('img')
            if img_elem:
                img_src = img_elem.get('src') or img_elem.get('data-src')
                product['image_url'] = urljoin(self.base_url, img_src) if img_src else None
            else:
                product['image_url'] = None
            
            # Stock/Availability
            stock_elem = product_element.select_one('[class*="stock"], [class*="availability"]')
            product['stock'] = stock_elem.get_text(strip=True) if stock_elem else None
            
            return product
        
        except Exception as e:
            logger.error(f"Error scraping product: {e}")
            return {}
    
    def scrape_product_listing(self, url):
        """
        Scrape all products from a listing page (category, search results, etc.).
        
        Args:
            url (str): The URL to scrape
            
        Returns:
            list: List of product dictionaries
        """
        soup = self.fetch_page(url)
        if not soup:
            return []
        
        products = []
        
        # Common product container selectors for e-commerce sites
        selectors = [
            'article.product',
            '.product-item',
            '[class*="product-card"]',
            'li[class*="product"]',
            'div[class*="product-list"] > div',
        ]
        
        product_elements = []
        for selector in selectors:
            product_elements = soup.select(selector)
            if product_elements:
                logger.info(f"Found {len(product_elements)} products using selector: {selector}")
                break
        
        for product_elem in product_elements:
            product = self.scrape_product(product_elem)
            if product.get('name'):  # Only add if we got a name
                products.append(product)
        
        logger.info(f"Scraped {len(products)} products from {url}")
        return products
    
    def scrape_product_details(self, url):
        """
        Scrape detailed information from a single product page.
        
        Args:
            url (str): The product URL
            
        Returns:
            dict: Detailed product information
        """
        soup = self.fetch_page(url)
        if not soup:
            return {}
        
        product = {
            'url': url,
            'name': None,
            'price': None,
            'description': None,
            'long_description': None,
            'specs': {},
            'images': [],
            'stock': None,
            'sku': None,
        }
        
        try:
            # Product name
            name_elem = soup.select_one('h1, .product-title')
            product['name'] = name_elem.get_text(strip=True) if name_elem else None
            
            # Price
            price_elem = soup.select_one('[class*="price"]')
            product['price'] = price_elem.get_text(strip=True) if price_elem else None
            
            # Short description
            desc_elem = soup.select_one('.product-description, .short-description')
            product['description'] = desc_elem.get_text(strip=True) if desc_elem else None
            
            # Long description
            long_desc = soup.select_one('.product-details, [class*="full-description"]')
            product['long_description'] = long_desc.get_text(strip=True) if long_desc else None
            
            # All images
            for img in soup.select('img[src*="product"], img[data-src*="product"]'):
                src = img.get('src') or img.get('data-src')
                if src:
                    product['images'].append(urljoin(self.base_url, src))
            
            # Stock status
            stock_elem = soup.select_one('[class*="stock"]')
            product['stock'] = stock_elem.get_text(strip=True) if stock_elem else None
            
            # SKU
            sku_elem = soup.select_one('[class*="sku"]')
            product['sku'] = sku_elem.get_text(strip=True) if sku_elem else None
            
            # Try to extract specs/attributes
            specs_section = soup.select('table.specs tr, .specs dl dt, .attributes li')
            for spec in specs_section:
                spec_text = spec.get_text(strip=True)
                if ':' in spec_text:
                    key, value = spec_text.split(':', 1)
                    product['specs'][key.strip()] = value.strip()
            
        except Exception as e:
            logger.error(f"Error scraping product details from {url}: {e}")
        
        return product
    
    def scrape_category(self, category_url, max_pages=None):
        """
        Scrape all products from a category (with pagination).
        
        Args:
            category_url (str): The category URL
            max_pages (int): Maximum number of pages to scrape (None = all)
            
        Returns:
            list: All products from category
        """
        all_products = []
        page = 1
        
        while True:
            if max_pages and page > max_pages:
                break
            
            # Handle pagination - adjust this based on actual URL structure
            paginated_url = f"{category_url}?page={page}" if '?' not in category_url else f"{category_url}&page={page}"
            
            logger.info(f"Scraping page {page}: {paginated_url}")
            products = self.scrape_product_listing(paginated_url)
            
            if not products:
                logger.info("No more products found, stopping pagination")
                break
            
            all_products.extend(products)
            page += 1
        
        return all_products
    
    def search_products(self, query, max_pages=1):
        """
        Search for products on Pimoroni.
        
        Args:
            query (str): Search query
            max_pages (int): Maximum pages to search
            
        Returns:
            list: Search results
        """
        search_url = f"{self.base_url}/search?q={query}"
        logger.info(f"Searching for: {query}")
        return self.scrape_category(search_url, max_pages=max_pages)
    
    def save_to_json(self, data, filename):
        """
        Save scraped data to JSON file.
        
        Args:
            data: Data to save
            filename (str): Output filename
        """
        try:
            with open(filename, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            logger.info(f"Saved {len(data)} items to {filename}")
        except Exception as e:
            logger.error(f"Error saving to JSON: {e}")
    
    def close(self):
        """Close the session."""
        self.session.close()


# Example usage
if __name__ == "__main__":
    scraper = PimoroniScraper(delay=2)
    
    # Example 1: Search for a product
    print("=== Example 1: Searching for Products ===")
    results = scraper.search_products("Raspberry Pi", max_pages=1)
    for product in results[:3]:
        print(f"\nName: {product.get('name')}")
        print(f"Price: {product.get('price')}")
        print(f"URL: {product.get('url')}")
    
    # Save results
    if results:
        scraper.save_to_json(results, 'pimoroni_search_results.json')
    
    # Example 2: Scrape a specific category
    print("\n=== Example 2: Scraping a Category ===")
    # Replace with actual category URL from Pimoroni
    category_products = scraper.scrape_category(
        'https://shop.pimoroni.com/collections/raspberry-pi',
        max_pages=1
    )
    print(f"Found {len(category_products)} products in category")
    
    # Example 3: Get product details
    if category_products and category_products[0].get('url'):
        print("\n=== Example 3: Product Details ===")
        details = scraper.scrape_product_details(category_products[0]['url'])
        print(f"Name: {details.get('name')}")
        print(f"Price: {details.get('price')}")
        print(f"SKU: {details.get('sku')}")
        if details.get('images'):
            print(f"Images: {len(details['images'])} found")
    
    scraper.close()
