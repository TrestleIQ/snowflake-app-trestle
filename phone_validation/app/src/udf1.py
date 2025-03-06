import requests
import _snowflake
import time
import json
class validate_phone:
    def __init__(self):
        self._phoneno = 0
        self._data = ""

    def process(self,ph_nos):
        url = "https://api.trestleiq.com/3.0/phone_intel"
           
        # Define headers with API key
        API_KEY = _snowflake.get_generic_secret_string('cred')
        
        headers = {
            "x-api-key": API_KEY
        }
        responses = []
        for phno in ph_nos:
            data = requests.get(url+f"?phone={phno}", headers=headers)
            data = data.json()
            responses.append((data))
            yield (phno,data)

    def end_partition(self):
        yield (self._phoneno, self._data)