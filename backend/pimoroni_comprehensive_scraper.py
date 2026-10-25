"""
Comprehensive Shopify scraper for Pimoroni.
Scrapes ALL products from the shop and saves to JSON.
"""

import requests
import json
import logging
import time
from urllib.parse import urljoin, urlparse, parse_qs
from collections import defaultdict

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class ComprehensivePimoroniScraper:
    """Comprehensive scraper to get ALL products from Pimoroni Shopify store."""
    
    def __init__(self, delay=0.5):
        """Initialize scraper."""
        self.base_url = 'https://shop.pimoroni.com'
        self.delay = delay
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })
        
        self.products = {}  # Use dict to deduplicate by handle
        self.stats = {
            'total_products': 0,
            'collections': 0,
            'requests': 0,
        }
    
    def get_sitemap_products(self):
        """
        Fetch products from sitemap.xml - often the most complete source.
        """
        try:
            logger.info("Fetching products from sitemap...")
            
            # Try to get product sitemap
            sitemap_url = f"{self.base_url}/sitemap.xml"
            response = self.session.get(sitemap_url, timeout=15)
            time.sleep(self.delay)
            self.stats['requests'] += 1
            
            if response.status_code != 200:
                logger.warning(f"Sitemap returned {response.status_code}")
                return []
            
            from xml.etree import ElementTree as ET
            root = ET.fromstring(response.content)
            
            # Find product sitemap URL
            sitemap_urls = []
            for elem in root.findall('.//{http://www.sitemaps.org/schemas/sitemap/0.9}loc'):
                url = elem.text
                if 'product' in url.lower():
                    sitemap_urls.append(url)
            
            logger.info(f"Found {len(sitemap_urls)} product sitemap(s)")
            
            products = []
            for sitemap_url in sitemap_urls:
                logger.info(f"Fetching sitemap: {sitemap_url}")
                response = self.session.get(sitemap_url, timeout=15)
                time.sleep(self.delay)
                self.stats['requests'] += 1
                
                if response.status_code != 200:
                    continue
                
                root = ET.fromstring(response.content)
                for elem in root.findall('.//{http://www.sitemaps.org/schemas/sitemap/0.9}loc'):
                    url = elem.text
                    if '/products/' in url:
                        # Extract handle from URL
                        parts = url.split('/products/')
                        if len(parts) > 1:
                            handle = parts[1].split('?')[0]
                            products.append(handle)
            
            logger.info(f"Sitemap contains {len(products)} product URLs")
            return products
        
        except Exception as e:
            logger.error(f"Sitemap error: {e}")
            return []
    
    def get_all_collections(self):
        """
        Get all collections from shop.
        """
        try:
            logger.info("Fetching all collections...")
            
            # Try collections JSON endpoint
            url = f"{self.base_url}/collections.json"
            response = self.session.get(url, timeout=15)
            time.sleep(self.delay)
            self.stats['requests'] += 1
            
            if response.status_code == 200:
                data = response.json()
                collections = data.get('collections', [])
                logger.info(f"Found {len(collections)} collections")
                return collections
        
        except Exception as e:
            logger.warning(f"Collections API error: {e}")
        
        return []
    
    def get_collection_products(self, collection_handle, limit=250):
        """Get all products from a collection with pagination."""
        products = []
        page = 1
        
        while True:
            try:
                url = f"{self.base_url}/collections/{collection_handle}/products.json"
                params = {
                    'limit': limit,
                    'page': page
                }
                
                logger.info(f"Fetching collection '{collection_handle}' page {page}...")
                response = self.session.get(url, params=params, timeout=15)
                time.sleep(self.delay)
                self.stats['requests'] += 1
                
                if response.status_code != 200:
                    break
                
                data = response.json()
                page_products = data.get('products', [])
                
                if not page_products:
                    break
                
                products.extend(page_products)
                logger.info(f"  Got {len(page_products)} products from page {page}")
                
                # Check if there are more pages
                if len(page_products) < limit:
                    break
                
                page += 1
            
            except Exception as e:
                logger.error(f"Error fetching collection page {page}: {e}")
                break
        
        return products
    
    def get_product_detail(self, product_handle):
        """Get full product details."""
        try:
            url = f"{self.base_url}/products/{product_handle}.json"
            
            response = self.session.get(url, timeout=15)
            time.sleep(self.delay)
            self.stats['requests'] += 1
            
            if response.status_code == 200:
                data = response.json()
                return data.get('product', {})
        
        except Exception as e:
            logger.error(f"Error fetching product {product_handle}: {e}")
        
        return {}
    
    def normalize_product(self, product_data):
        """Convert raw product data to normalized format."""
        return {
            'id': product_data.get('id'),
            'handle': product_data.get('handle'),
            'name': product_data.get('title'),
            'vendor': product_data.get('vendor'),
            'type': product_data.get('product_type'),
            'description': product_data.get('body_html'),
            'tags': product_data.get('tags', '').split(', ') if product_data.get('tags') else [],
            'images': [
                {
                    'src': img.get('src'),
                    'alt': img.get('alt'),
                }
                for img in product_data.get('images', [])
            ],
            'variants': [
                {
                    'id': v.get('id'),
                    'title': v.get('title'),
                    'sku': v.get('sku'),
                    'price': v.get('price'),
                    'compare_at_price': v.get('compare_at_price'),
                    'available': v.get('available'),
                    'grams': v.get('grams'),
                }
                for v in product_data.get('variants', [])
            ],
            'url': f"{self.base_url}/products/{product_data.get('handle')}",
            'published_at': product_data.get('published_at'),
            'created_at': product_data.get('created_at'),
            'updated_at': product_data.get('updated_at'),
        }
    
    def scrape_all_products(self, use_collections=True, use_sitemap=True):
        """
        Scrape all products using multiple methods.
        """
        logger.info("=" * 60)
        logger.info("Starting comprehensive product scrape...")
        logger.info("=" * 60)
        
        # Method 1: Sitemap (fastest, gets all products)
        if use_sitemap:
            logger.info("\n[Method 1] Fetching from Sitemap...")
            product_handles = self.get_sitemap_products()
            
            for i, handle in enumerate(product_handles, 1):
                if handle not in self.products:
                    product_data = self.get_product_detail(handle)
                    if product_data:
                        self.products[handle] = self.normalize_product(product_data)
                        logger.info(f"  [{i}/{len(product_handles)}] {product_data.get('title')}")
        
        # Method 2: Collections (for completeness and verification)
        if use_collections:
            logger.info("\n[Method 2] Fetching from Collections...")
            collections = self.get_all_collections()
            self.stats['collections'] = len(collections)
            
            for collection in collections:
                handle = collection.get('handle')
                name = collection.get('title')
                logger.info(f"\nCollection: {name}")
                
                products = self.get_collection_products(handle)
                
                for product in products:
                    prod_handle = product.get('handle')
                    if prod_handle not in self.products:
                        # Normalize the product data
                        self.products[prod_handle] = self.normalize_product(product)
                        logger.info(f"  [new] {product.get('title')}")
        
        self.stats['total_products'] = len(self.products)
        
        logger.info("\n" + "=" * 60)
        logger.info("Scrape Complete!")
        logger.info("=" * 60)
        logger.info(f"Total products: {self.stats['total_products']}")
        logger.info(f"Collections crawled: {self.stats['collections']}")
        logger.info(f"HTTP requests made: {self.stats['requests']}")
        
        return list(self.products.values())
    
    def save_products(self, filename='pimoroni_all_products.json'):
        """Save all products to JSON file."""
        try:
            data = {
                'metadata': {
                    'shop': 'Pimoroni',
                    'shop_url': self.base_url,
                    'total_products': self.stats['total_products'],
                    'collections': self.stats['collections'],
                    'requests': self.stats['requests'],
                    'scrape_timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
                },
                'products': list(self.products.values())
            }
            
            with open(filename, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            
            logger.info(f"\n[OK] Saved {self.stats['total_products']} products to {filename}")
            
            # Print file size
            import os
            file_size = os.path.getsize(filename)
            file_size_mb = file_size / (1024 * 1024)
            logger.info(f"     File size: {file_size_mb:.2f} MB")
            
            return True
        
        except Exception as e:
            logger.error(f"Error saving products: {e}")
            return False
    
    def save_csv(self, filename='pimoroni_all_products.csv'):
        """Save products to CSV for spreadsheet apps."""
        try:
            import csv
            
            products = list(self.products.values())
            if not products:
                logger.warning("No products to save")
                return False
            
            with open(filename, 'w', newline='', encoding='utf-8') as f:
                writer = csv.DictWriter(f, fieldnames=[
                    'id', 'handle', 'name', 'vendor', 'type', 'tags',
                    'price', 'compare_at_price', 'url', 'image_count',
                    'variant_count', 'published_at'
                ])
                
                writer.writeheader()
                
                for product in products:
                    price = product['variants'][0]['price'] if product['variants'] else 'N/A'
                    compare_price = product['variants'][0]['compare_at_price'] if product['variants'] else None
                    
                    writer.writerow({
                        'id': product['id'],
                        'handle': product['handle'],
                        'name': product['name'],
                        'vendor': product['vendor'],
                        'type': product['type'],
                        'tags': '; '.join(product['tags']),
                        'price': price,
                        'compare_at_price': compare_price,
                        'url': product['url'],
                        'image_count': len(product['images']),
                        'variant_count': len(product['variants']),
                        'published_at': product['published_at'],
                    })
            
            logger.info(f"[OK] Saved {len(products)} products to {filename}")
            return True
        
        except Exception as e:
            logger.error(f"Error saving CSV: {e}")
            return False


# Example usage
if __name__ == "__main__":
    scraper = ComprehensivePimoroniScraper(delay=0.3)
    
    print("\n[*] Starting Pimoroni comprehensive scrape...\n")
    
    # Scrape all products
    products = scraper.scrape_all_products(
        use_collections=True,
        use_sitemap=True
    )
    
    # Save to JSON
    scraper.save_products('pimoroni_all_products.json')
    
    # Also save as CSV
    scraper.save_csv('pimoroni_all_products.csv')
    
    # Print summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"Total products scraped: {len(products)}")
    if products:
        print(f"\nFirst 5 products:")
        for product in products[:5]:
            print(f"  - {product['name']}")
            if product['variants']:
                print(f"    Price: {product['variants'][0]['price']}")
        
        print(f"\nSample product details:")
        sample = products[0]
        print(f"  Name: {sample['name']}")
        print(f"  Vendor: {sample['vendor']}")
        print(f"  Type: {sample['type']}")
        print(f"  Images: {len(sample['images'])}")
        print(f"  Variants: {len(sample['variants'])}")
        tags_str = ', '.join(sample['tags'][:5]) if sample['tags'] else 'None'
        print(f"  Tags: {tags_str}")
