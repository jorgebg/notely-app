# Kill switch: receives every budget update (Pub/Sub) and, once the spend passes the budget,
# disconnects billing from the demo project. Everything in that project stops; nothing else does.
import base64
import json
import os

import functions_framework
from google.cloud import billing_v1

PROJECT = os.environ["DEMO_PROJECT_ID"]


@functions_framework.cloud_event
def stop_billing(cloud_event):
    update = json.loads(base64.b64decode(cloud_event.data["message"]["data"]))
    cost, budget = update["costAmount"], update["budgetAmount"]
    if cost <= budget:
        print(f"{update['currencyCode']} {cost} of {budget}: nothing to do")
        return

    # Unlinking is idempotent, and the role we hold (Project Billing Manager) can unlink but
    # not read the billing info: no "is it already off?" check.
    client = billing_v1.CloudBillingClient()
    client.update_project_billing_info(
        name=f"projects/{PROJECT}", project_billing_info={"billing_account_name": ""})
    print(f"{update['currencyCode']} {cost} > {budget}: billing disconnected from {PROJECT}")
