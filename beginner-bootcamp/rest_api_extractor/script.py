import requests
import os
from dotenv import load_dotenv

load_dotenv()

POLYGON_API_KEY = os.getenv("POLYGON_API_KEY")

print(POLYGON_API_KEY)

def get_api_data(url):
    response = requests.get(url)
    return response.json()