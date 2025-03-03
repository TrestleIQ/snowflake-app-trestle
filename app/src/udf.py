
import requests
import _snowflake
from snowflake.snowpark import Session
import time

def validate_phone(phno):
    url = "https://api.trestleiq.com/3.0/phone_intel"
       
    # Define headers with API key
    API_KEY = _snowflake.get_generic_secret_string('cred')
    
    headers = {
        "x-api-key": API_KEY
    }
    data = requests.get(url+f"?phone={phno}", headers=headers)
    data = data.json()
    time.sleep(0.06)
    return data