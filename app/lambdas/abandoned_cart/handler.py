import json
import os

import boto3

NOTIFICATIONS_TOPIC_ARN = os.environ["NOTIFICATIONS_TOPIC_ARN"]

sns = boto3.client("sns")


def handler(event, _context):
    failures = []
    for record in event["Records"]:
        try:
            cart = record["dynamodb"]["OldImage"]
            user = cart.get("email", cart["user_id"])["S"]
            items = cart.get("items", {}).get("L", [])
            units = sum(int(i["M"]["quantity"]["N"]) for i in items)
            sns.publish(
                TopicArn=NOTIFICATIONS_TOPIC_ARN,
                Subject="ShopFlow: carrito abandonado",
                Message=(
                    f"El carrito de {user} ha caducado sin convertirse en pedido.\n"
                    f"Tenia {len(items)} productos distintos ({units} unidades).\n"
                    "Buen momento para mandarle un cupon de descuento."
                ),
            )
            print(json.dumps({"user": user, "products": len(items), "result": "notified"}))
        except Exception as exc:
            print(json.dumps({"sequence": record["dynamodb"].get("SequenceNumber"), "error": repr(exc)}))
            failures.append({"itemIdentifier": record["dynamodb"]["SequenceNumber"]})
    return {"batchItemFailures": failures}
