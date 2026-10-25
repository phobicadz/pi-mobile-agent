"""
Enhanced Pimoroni scraper that handles JavaScript-rendered content.
Requires: pip install selenium webdriver-manager beautifulsoup4
Or: pip install playwright beautifulsoup4
"""

import json
import time
import logging
from urllib.parse import urljoin
from bs4 import BeautifulSoup

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class PimoroniScraperJS:
    """Pimoroni scraper using Selenium for JavaScript rendering."""
    
    def __init__(self, headless=True, delay=2):
        """
        Initialize with Selenium WebDriver.
        
        Args:
            headless (bool): Run browser in headless mode
            delay (int): Delay between requests
        """
        try:
            from selenium import webdriver
            from selenium.webdriver.common.by import By
            from selenium.webdriver.support.ui import WebDriverWait
            from selenium.webdriver.support import expected_conditions as EC
            self.webdriver = webdriver
            self.By = By
            self.WebDriverWait = WebDriverWait
            self.EC = EC
        except ImportError:
            raise ImportError("Selenium not installed. Run: pip install selenium webdriver-manager")
        
        self.base_url = 'https://shop.pimoroni.com'
        self.delay = delay
        self.driver = None
        self.headless = headless
    
    def init_driver(self):
        """Initialize the Selenium WebDriver."""
        try:
            from selenium.webdriver.chrome.options import Options
            from webdriver_manager.chrome import ChromeDriverManager
            from selenium.webdriver.chrome.service import Service
            
            chrome_options = Options()
            if self.headless:
                chrome_options.add_argument('--headless')
            chrome_options.add_argument('--no-sandbox')
            chrome_options.add_argument('--disable-dev-shm-usage')
            chrome_options.add_argument('--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/91.0.4472.124')
            
            service = Service(ChromeDriverManager().install())
            self.driver = self.webdriver.Chrome(service=service, options=chrome_options)
            logger.info("Chrome WebDriver initialized")
        except ImportError:
            raise ImportError("Selenium dependencies not installed. Run: pip install selenium webdriver-manager")
    
    def fetch_page_js(self, url, wait_selector=None, wait_time=10):
        """
        Fetch page with JavaScript rendering.
        
        Args:
            url (str): URL to fetch
            wait_selector (str): CSS selector to wait for (product elements)
            wait_time (int): Seconds to wait for elements
            
        Returns:
            BeautifulSoup: Parsed HTML
        """
        if not self.driver:
            self.init_driver()
        
        try:
            logger.info(f"Fetching (with JS): {url}")
            self.driver.get(url)
            
            # Wait for products to load
            if wait_selector:
                self.WebDriverWait(self.driver, wait_time).until(
                    self.EC.presence_of_all_elements_located((self.By.CSS_SELECTOR, wait_selector))
                )
                logger.info(f"Products loaded using selector: {wait_selector}")
            else:
                # Default wait for common product selectors
                for selector in ['article.product', '[class*="product-card"]', '.product-item']:
                    try:
                        self.WebDriverWait(self.driver, 3).until(
                            self.EC.presence_of_all_elements_located((self.By.CSS_SELECTOR, selector))
                        )
                        logger.info(f"Found products with selector: {selector}")
                        break
                    except:
                        continue
            
            time.sleep(self.delay)
            return BeautifulSoup(self.driver.page_source, 'html.parser')
        
        except Exception as e:
            logger.error(f"Error fetching {url}: {e}")
            return None
    
    def scrape_product(self, product_element):
        """Extract product info from element."""
        try:
            product = {}
            
            # Product name
            name_elem = product_element.select_one('h3, h4, .product-title, [data-product-name]')
            product['name'] = name_elem.get_text(strip=True) if name_elem else None
            
            # Product URL
            link_elem = product_element.select_one('a[href*="/products/"]')
            product['url'] = urljoin(self.base_url, link_elem['href']) if link_elem else None
            
            # Price
            price_elem = product_element.select_one('[class*="price"], .product-price')
            product['price'] = price_elem.get_text(strip=True) if price_elem else None
            
            # Description
            desc_elem = product_element.select_one('.product-description, .description, [data-description]')
            product['description'] = desc_elem.get_text(strip=True) if desc_elem else None
            
            # Image
            img_elem = product_element.select_one('img')
            if img_elem:
                img_src = img_elem.get('src') or img_elem.get('data-src')
                product['image_url'] = urljoin(self.base_url, img_src) if img_src else None
            else:
                product['image_url'] = None
            
            # Stock
            stock_elem = product_element.select_one('[class*="stock"], [class*="availability"]')
            product['stock'] = stock_elem.get_text(strip=True) if stock_elem else None
            
            return product
        
        except Exception as e:
            logger.error(f"Error scraping product: {e}")
            return {}
    
    def scrape_search_results(self, url, max_results=None):
        """Scrape search results page."""
        soup = self.fetch_page_js(url)
        if not soup:
            return []
        
        products = []
        
        # Try various product selectors
        selectors = [
            'article.product',
            '[class*="ProductCard"]',
            '[data-product-id]',
            '.product-item',
            '[class*="productItem"]',
        ]
        
        for selector in selectors:
            product_elements = soup.select(selector)
            if product_elements:
                logger.info(f"Found {len(product_elements)} products with selector: {selector}")
                break
        
        for product_elem in product_elements:
            product = self.scrape_product(product_elem)
            if product.get('name'):
                products.append(product)
                if max_results and len(products) >= max_results:
                    break
        
        return products
    
    def search(self, query, max_results=50):
        """Search for products."""
        search_url = f"{self.base_url}/search?q={query.replace(' ', '+')}"
        logger.info(f"Searching for: {query}")
        return self.scrape_search_results(search_url, max_results=max_results)
    
    def scrape_product_detail(self, url):
        """Scrape a single product page with all details."""
        soup = self.fetch_page_js(url)
        if not soup:
            return {}
        
        product = {
            'url': url,
            'name': None,
            'price': None,
            'description': None,
            'specs': {},
            'images': [],
            'stock': None,
        }
        
        try:
            # Name
            product['name'] = soup.select_one('h1, .product-title').get_text(strip=True)
            
            # Price
            price_elem = soup.select_one('[class*="price"]')
            if price_elem:
                product['price'] = price_elem.get_text(strip=True)
            
            # Description
            desc_elem = soup.select_one('[class*="description"]')
            if desc_elem:
                product['description'] = desc_elem.get_text(strip=True)
            
            # Images
            for img in soup.select('img[src*="product"], img[data-src*="product"]'):
                src = img.get('src') or img.get('data-src')
                if src:
                    product['images'].append(urljoin(self.base_url, src))
            
            # Stock status
            stock_elem = soup.select_one('[class*="stock"]')
            if stock_elem:
                product['stock'] = stock_elem.get_text(strip=True)
        
        except Exception as e:
            logger.error(f"Error scraping product details: {e}")
        
        return product
    
    def save_json(self, data, filename):
        """Save to JSON file."""
        try:
            with open(filename, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            logger.info(f"Saved {len(data)} items to {filename}")
        except Exception as e:
            logger.error(f"Error saving JSON: {e}")
    
    def close(self):
        """Close the browser."""
        if self.driver:
            self.driver.quit()
            logger.info("WebDriver closed")


# Example usage
if __name__ == "__main__":
    scraper = PimoroniScraperJS(headless=True, delay=1)
    
    try:
        print("=== Searching for 'Raspberry Pi' ===")
        results = scraper.search("Raspberry Pi", max_results=10)
        
        print(f"\nFound {len(results)} products:\n")
        for i, product in enumerate(results, 1):
            print(f"{i}. {product.get('name')}")
            print(f"   Price: {product.get('price')}")
            print(f"   URL: {product.get('url')}\n")
        
        # Save results
        if results:
            scraper.save_json(results, 'pimoroni_results.json')
            
            # Get details of first product
            if results[0].get('url'):
                print("=== Getting product details ===")
                details = scraper.scrape_product_detail(results[0]['url'])
                print(f"Name: {details.get('name')}")
                print(f"Price: {details.get('price')}")
                print(f"Stock: {details.get('stock')}")
                if details.get('images'):
                    print(f"Images: {len(details['images'])}")
    
    finally:
        scraper.close()
