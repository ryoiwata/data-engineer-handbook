# REST API Extractor

This script extracts stock ticker data from the Polygon.io API.

## Setup

1. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

2. Set up your API key by creating a `.env` file:
   ```bash
   echo "POLYGON_API_KEY=your_actual_api_key_here" > .env
   ```

3. Run the script:
   ```bash
   python script.py
   ```

## Features

- Fetches stock ticker data from Polygon.io API
- Handles pagination automatically
- Includes error handling for API errors and rate limiting
- Validates API key before making requests

## Error Handling

The script now includes proper error handling for:
- Missing API key
- API request failures
- Rate limiting (429 errors)
- API error responses
- Missing data fields in responses
