import requests
import os
import csv
from dotenv import load_dotenv


def get_api_data(url):
    """
    Get data from the API
    """
    response = requests.get(url)
    return response.json()


if __name__ == "__main__":
    load_dotenv()

    POLYGON_API_KEY = os.getenv("POLYGON_API_KEY")

    LIMIT = 100

    url = f'https://api.polygon.io/v3/reference/tickers?market=stocks&active=true&order=asc&limit={LIMIT}&sort=ticker&apiKey={POLYGON_API_KEY}'
    data = get_api_data(url)
    
    tickers = []
    print(data.keys())
    
    # Check if the response has an error
    if "error" in data:
        print(f"API Error: {data['error']}")
        exit(1)
    
    # Add tickers from first page
    if "results" in data:
        for ticker in data["results"]:
            tickers.append(ticker)
    
    while "next_url" in data:
        print("Requesting next page: ", data["next_url"])
        response = requests.get(data["next_url"] + f'&apiKey={POLYGON_API_KEY}')
        data = response.json()
        
        print(data.keys())
        
        # Check if the response has an error
        if "error" in data:
            print(f"API Error: {data['error']}")
            break
            
        # Add tickers from current page
        if "results" in data:
            for ticker in data["results"]:
                tickers.append(ticker)
    
    print(f"Total tickers collected: {len(tickers)}")
    
    # Write tickers to CSV file
    if tickers:
        csv_filename = 'tickers.csv'
        fieldnames = ['ticker', 'name', 'market', 'locale', 'primary_exchange', 'type', 'active', 'currency_name', 'cik', 'composite_figi', 'share_class_figi', 'last_updated_utc']
        
        with open(csv_filename, 'w', newline='', encoding='utf-8') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(tickers)
        
        print(f"Ticker data written to {csv_filename}")
    else:
        print("No ticker data to write to CSV")