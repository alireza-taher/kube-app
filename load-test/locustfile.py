import os
import random
import urllib3
from locust import HttpUser, task, between

# Disable warnings for self-signed SSL certificates
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class CalculateUser(HttpUser):
    host = "https://webapp.local"
    wait_time = between(1, 3)

    @task
    def calculate(self):
        api_key = os.environ.get("APIKEY", "")
        headers = {"apikey": api_key}
        param_value = random.randint(20, 50)

        self.client.get(
            "/calculate",
            params={"param": param_value},
            headers=headers,
            verify=False
        )
