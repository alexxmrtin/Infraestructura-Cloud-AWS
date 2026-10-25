import json
import os
from datetime import date, timedelta

import boto3

STATS_TABLE = os.environ["STATS_TABLE"]
NOTIFICATIONS_TOPIC_ARN = os.environ["NOTIFICATIONS_TOPIC_ARN"]

stats = boto3.resource("dynamodb").Table(STATS_TABLE)
sns = boto3.client("sns")


def handler(event, _context):
    day = event.get("day") or (date.today() - timedelta(days=1)).isoformat()
    item = stats.get_item(Key={"pk": f"DAY#{day}"}).get("Item", {})
    orders = int(item.get("orders", 0))
    revenue = f"{item.get('revenue', 0):.2f}"

    sns.publish(
        TopicArn=NOTIFICATIONS_TOPIC_ARN,
        Subject=f"ShopFlow: resumen del {day}",
        Message=f"Pedidos recibidos el {day}: {orders}\nImporte total: {revenue} EUR",
    )
    print(json.dumps({"day": day, "orders": orders, "revenue": revenue}))
    return {"day": day, "orders": orders, "revenue": revenue}
