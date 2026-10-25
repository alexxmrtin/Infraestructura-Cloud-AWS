import json
import os
import time
from decimal import Decimal

PAYMENT_LIMIT = Decimal(os.environ.get("PAYMENT_LIMIT", "200"))
METRICS_NAMESPACE = os.environ.get("METRICS_NAMESPACE", "ShopFlow")
METRICS_ENVIRONMENT = os.environ.get("METRICS_ENVIRONMENT", "local")


class PaymentDeclined(Exception):
    pass


def log_metrics(metrics, **fields):
    print(
        json.dumps(
            {
                "_aws": {
                    "Timestamp": int(time.time() * 1000),
                    "CloudWatchMetrics": [
                        {
                            "Namespace": METRICS_NAMESPACE,
                            "Dimensions": [["Environment"]],
                            "Metrics": [{"Name": name, "Unit": unit} for name, (_, unit) in metrics.items()],
                        }
                    ],
                },
                "Environment": METRICS_ENVIRONMENT,
                **{name: value for name, (value, _) in metrics.items()},
                **fields,
            }
        )
    )


def handler(event, _context):
    order_id = event["order_id"]
    total = Decimal(event["total"])

    if total > PAYMENT_LIMIT:
        log_metrics({"PaymentsDeclined": (1, "Count")}, order_id=order_id, total=str(total), result="declined")
        raise PaymentDeclined(f"Pago rechazado: {total} EUR supera el limite de {PAYMENT_LIMIT} EUR")

    payment_id = f"pay-{order_id}"
    log_metrics(
        {"PaymentsAccepted": (1, "Count")}, order_id=order_id, total=str(total), payment_id=payment_id, result="paid"
    )
    return {"payment_id": payment_id}
