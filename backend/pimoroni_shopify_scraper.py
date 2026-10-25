"""
Shopify-optimized Pimoroni scraper.
Shopify sites have built-in JSON APIs that are much more efficient than scraping.
"""

import requests
import json
import logging
from urllib.parse import urljoin
import time

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class ShopifyPimoroniScraper:
    """Scraper optimized for Shopify-based Pimoroni shop."""
    
    def __init__(self, delay=1):
        """Initialize Shopify scraper."""
        self.base_url = 'https://shop.pimoroni.com'
        self.delay = delay
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })
        
        # Shopify API endpoints
        self.shopify_api = f"{self.base_url}/admin/api/2024-01"  # May need adjustment
        
        # Algolia search (Pimoroni uses this)
        self.algolia_app_id = "M00M3RFW1A"  # From HTML
        self.algolia_api_key = None  # May be needed
    
    def search_via_shopify_api(self, query, limit=250):
        """
        Search using Shopify's GraphQL API (if public endpoint available).
        This is the most efficient method.
        """
        try:
            # Try Shopify's storefront API
            url = f"{self.base_url}/api/2024-01/graphql.json"
            
            # GraphQL query for product search
            query_body = {
                "query": """
                {
                    products(first: %d, query: "%s") {
                        edges {
                            node {
                                id
                                title
                                handle
                                description
                                onlineStoreUrl
                                images(first: 1) {
                                    edges {
                                        node {
                                            url
                                        }
                                    }
                                }
                                variants(first: 1) {
                                    edges {
                                        node {
                                            price
                                            availableForSale
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                """ % (limit, query)
            }
            
            logger.info(f"Searching Shopify GraphQL API for: {query}")
            response = self.session.post(url, json=query_body, timeout=15)
            
            if response.status_code == 200:
                data = response.json()
                products = []
                
                if 'data' in data and 'products' in data['data']:
                    for edge in data['data']['products']['edges']:
                        node = edge['node']
                        product = {
                            'name': node.get('title'),
                            'handle': node.get('handle'),
                            'description': node.get('description'),
                            'url': node.get('onlineStoreUrl'),
                            'image': node.get('images', {}).get('edges', [{}])[0].get('node', {}).get('url'),
                            'price': node.get('variants', {}).get('edges', [{}])[0].get('node', {}).get('price'),
                            'in_stock': node.get('variants', {}).get('edges', [{}])[0].get('node', {}).get('availableForSale'),
                        }
                        products.append(product)
                
                logger.info(f"GraphQL API returned {len(products)} products")
                return products
            else:
                logger.warning(f"GraphQL API returned {response.status_code}")
                return []
        
        except Exception as e:
            logger.error(f"GraphQL API error: {e}")
            return []
    
    def search_via_json_endpoint(self, query, limit=250):
        """
        Try Shopify's JSON product endpoint.
        Some Shopify stores expose /products.json or /search/suggest.json
        """
        try:
            # Try search suggestions first (fastest)
            url = f"{self.base_url}/search/suggest.json"
            params = {
                'q': query,
                'resources[type]': 'product',
                'resources[limit]': limit
            }
            
            logger.info(f"Trying JSON endpoint: {url}")
            response = self.session.get(url, params=params, timeout=15)
            time.sleep(self.delay)
            
            if response.status_code == 200:
                data = response.json()
                products = []
                
                if 'resources' in data and 'results' in data['resources']:
                    for product in data['resources']['results'].get('products', []):
                        products.append({
                            'name': product.get('title'),
                            'url': urljoin(self.base_url, product.get('url', '')),
                            'image': product.get('image'),
                            'price': product.get('price'),
                            'description': product.get('description'),
                        })
                
                logger.info(f"JSON endpoint returned {len(products)} products")
                return products
        
        except Exception as e:
            logger.warning(f"JSON endpoint error: {e}")
        
        return []
    
    def search_via_algolia(self, query, limit=100):
        """
        Search using Algolia directly (Pimoroni uses Algolia).
        This is often more powerful than Shopify's native search.
        """
        try:
            # Algolia search endpoint
            algolia_url = f"https://{self.algolia_app_id}-dsn.algolia.net/1/indexes/shopify_products/query"
            
            headers = {
                'X-Algolia-API-Key': 'c42d562520daf1cb87cd4228356e18b9',  # Public key often visible in JS
                'X-Algolia-Application-Id': self.algolia_app_id,
                'Content-Type': 'application/json',
            }
            
            payload = {
                "params": f"query={query}&hitsPerPage={limit}&facetFilters=[]"
            }
            
            logger.info(f"Searching Algolia for: {query}")
            response = self.session.post(algolia_url, json=payload, headers=headers, timeout=15)
            time.sleep(self.delay)
            
            if response.status_code == 200:
                data = response.json()
                products = []
                
                for hit in data.get('hits', []):
                    product = {
                        'name': hit.get('title'),
                        'handle': hit.get('handle'),
                        'url': urljoin(self.base_url, f"/products/{hit.get('handle')}"),
                        'price': hit.get('variants', [{}])[0].get('price'),
                        'price_range': hit.get('price_range'),
                        'description': hit.get('description'),
                        'image': hit.get('image', {}).get('src') if isinstance(hit.get('image'), dict) else hit.get('image'),
                        'vendor': hit.get('vendor'),
                        'tags': hit.get('tags', []),
                    }
                    products.append(product)
                
                logger.info(f"Algolia returned {len(products)} products")
                return products
            else:
                logger.warning(f"Algolia returned {response.status_code}")
                return []
        
        except Exception as e:
            logger.error(f"Algolia error: {e}")
            return []
    
    def get_collection_products(self, collection_handle, limit=250):
        """Get all products from a collection/category."""
        try:
            # Shopify collections endpoint
            url = f"{self.base_url}/collections/{collection_handle}/products.json"
            
            logger.info(f"Fetching collection: {collection_handle}")
            response = self.session.get(url, timeout=15)
            time.sleep(self.delay)
            
            if response.status_code == 200:
                data = response.json()
                products = []
                
                for product in data.get('products', []):
                    prod = {
                        'name': product.get('title'),
                        'handle': product.get('handle'),
                        'url': urljoin(self.base_url, f"/products/{product.get('handle')}"),
                        'price': product.get('variants', [{}])[0].get('price') if product.get('variants') else None,
                        'description': product.get('body_html'),
                        'image': product.get('featured_image', {}).get('src') if product.get('featured_image') else None,
                        'vendor': product.get('vendor'),
                    }
                    products.append(prod)
                
                logger.info(f"Collection returned {len(products)} products")
                return products
        
        except Exception as e:
            logger.error(f"Collection error: {e}")
        
        return []
    
    def get_product_detail(self, product_handle):
        """Get full details for a single product."""
        try:
            url = f"{self.base_url}/products/{product_handle}.json"
            
            logger.info(f"Fetching product: {product_handle}")
            response = self.session.get(url, timeout=15)
            time.sleep(self.delay)
            
            if response.status_code == 200:
                data = response.json()
                product = data.get('product', {})
                
                return {
                    'name': product.get('title'),
                    'handle': product.get('handle'),
                    'description': product.get('body_html'),
                    'vendor': product.get('vendor'),
                    'product_type': product.get('product_type'),
                    'tags': product.get('tags'),
                    'images': [img.get('src') for img in product.get('images', [])],
                    'variants': [
                        {
                            'title': v.get('title'),
                            'price': v.get('price'),
                            'available': v.get('available'),
                            'sku': v.get('sku'),
                        }
                        for v in product.get('variants', [])
                    ],
                    'url': f"{self.base_url}/products/{product.get('handle')}",
                }
        
        except Exception as e:
            logger.error(f"Product detail error: {e}")
        
        return {}
    
    def search(self, query, method='algolia', limit=100):
        """
        Search for products using best available method.
        
        Args:
            query (str): Search query
            method (str): 'algolia' (best), 'graphql', 'json', or 'auto' to try all
            limit (int): Results limit
        """
        if method == 'auto':
            # Try in order of efficiency
            results = self.search_via_algolia(query, limit)
            if results:
                return results
            
            results = self.search_via_json_endpoint(query, limit)
            if results:
                return results
            
            return self.search_via_shopify_api(query, limit)
        
        elif method == 'algolia':
            return self.search_via_algolia(query, limit)
        
        elif method == 'json':
            return self.search_via_json_endpoint(query, limit)
        
        elif method == 'graphql':
            return self.search_via_shopify_api(query, limit)
        
        return []
    
    def save_json(self, data, filename):
        """Save results to JSON."""
        try:
            with open(filename, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            logger.info(f"Saved {len(data)} items to {filename}")
        except Exception as e:
            logger.error(f"Save error: {e}")


# Example usage
if __name__ == "__main__":
    scraper = ShopifyPimoroniScraper(delay=1)
    
    print("=== Searching Pimoroni (Shopify) ===\n")
    
    # Try multiple methods
    results = scraper.search("Raspberry Pi", method='auto', limit=50)
    
    print(f"Found {len(results)} products:\n")
    for i, product in enumerate(results[:10], 1):
        print(f"{i}. {product.get('name')}")
        if product.get('price'):
            print(f"   Price: £{product.get('price')}")
        if product.get('url'):
            print(f"   URL: {product.get('url')}")
        if product.get('description'):
            desc = product.get('description')[:100]
            print(f"   Description: {desc}...")
        print()
    
    # Save results
    if results:
        scraper.save_json(results, 'pimoroni_shopify_results.json')
        
        # Get detailed info for first product
        if results[0].get('handle'):
            print("\n=== Product Details ===")
            details = scraper.get_product_detail(results[0]['handle'])
            print(f"Name: {details.get('name')}")
            print(f"Vendor: {details.get('vendor')}")
            print(f"Type: {details.get('product_type')}")
            print(f"Variants: {len(details.get('variants', []))}")
            print(f"Images: {len(details.get('images', []))}")
            if details.get('variants'):
                print(f"First variant: {details['variants'][0].get('title')} - £{details['variants'][0].get('price')}")
    
    # Example: Get all products from a collection
    print("\n=== Getting Collection Products ===")
    collection_products = scraper.get_collection_products("raspberry-pi", limit=20)
    print(f"Found {len(collection_products)} products in collection")
