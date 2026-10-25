import json
import os
import time
from decimal import Decimal

import boto3

STATS_TABLE = os.environ["STATS_TABLE"]
MARKER_TTL_SECONDS = 7 * 24 * 3600
METRICS_NAMESPACE = os.environ.get("METRICS_NAMESPACE", "ShopFlow")
METRICS_ENVIRONMENT = os.environ.get("METRICS_ENVIRONMENT", "local")

dynamodb = boto3.client("dynamodb")


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


def count_order(order):
    day = order["created_at"][:10]
    try:
        dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Put": {
                        "TableName": STATS_TABLE,
                        "Item": {
                            "pk": {"S": f"ORDER#{order['order_id']}"},
                            "expires_at": {"N": str(int(time.time()) + MARKER_TTL_SECONDS)},
                        },
                        "ConditionExpression": "attribute_not_exists(pk)",
                    }
                },
                {
                    "Update": {
                        "TableName": STATS_TABLE,
                        "Key": {"pk": {"S": f"DAY#{day}"}},
                        "UpdateExpression": "ADD orders :one, revenue :total",
                        "ExpressionAttributeValues": {
                            ":one": {"N": "1"},
                            ":total": {"N": str(Decimal(order["total"]))},
                        },
                    }
                },
            ]
        )
        return "counted"
    except dynamodb.exceptions.TransactionCanceledException as exc:
        reasons = exc.response.get("CancellationReasons", [])
        if reasons and reasons[0].get("Code") == "ConditionalCheckFailed":
            return "already_counted"
        raise


def handler(event, _context):
    failures = []
    for record in event["Records"]:
        try:
            order = json.loads(record["body"])
            result = count_order(order)
            if result == "counted":
                log_metrics(
                    {"OrdersPlaced": (1, "Count"), "OrderValue": (float(Decimal(order["total"])), "None")},
                    order_id=order["order_id"],
                    result=result,
                )
            else:
                print(json.dumps({"order_id": order["order_id"], "result": result}))
        except Exception as exc:
            print(json.dumps({"message_id": record["messageId"], "error": repr(exc)}))
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}
