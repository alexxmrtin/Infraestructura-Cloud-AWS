import json
import os
import time

import boto3

STOCK_TABLE = os.environ["STOCK_TABLE"]
ORDERS_TABLE = os.environ["ORDERS_TABLE"]
METRICS_NAMESPACE = os.environ.get("METRICS_NAMESPACE", "ShopFlow")
METRICS_ENVIRONMENT = os.environ.get("METRICS_ENVIRONMENT", "local")

dynamodb = boto3.client("dynamodb")


class OutOfStock(Exception):
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


def order_update(order_id, reserve):
    if reserve:
        return {
            "Update": {
                "TableName": ORDERS_TABLE,
                "Key": {"order_id": {"S": order_id}},
                "UpdateExpression": "SET stock_reserved = :yes",
                "ConditionExpression": "attribute_exists(order_id) AND attribute_not_exists(stock_reserved)",
                "ExpressionAttributeValues": {":yes": {"BOOL": True}},
            }
        }
    return {
        "Update": {
            "TableName": ORDERS_TABLE,
            "Key": {"order_id": {"S": order_id}},
            "UpdateExpression": "REMOVE stock_reserved",
            "ConditionExpression": "stock_reserved = :yes",
            "ExpressionAttributeValues": {":yes": {"BOOL": True}},
        }
    }


def stock_update(item, reserve):
    quantity = {"N": str(int(item["quantity"]))}
    if reserve:
        return {
            "Update": {
                "TableName": STOCK_TABLE,
                "Key": {"product_id": {"N": str(int(item["product_id"]))}},
                "UpdateExpression": "SET stock = stock - :q",
                "ConditionExpression": "stock >= :q",
                "ExpressionAttributeValues": {":q": quantity},
            }
        }
    return {
        "Update": {
            "TableName": STOCK_TABLE,
            "Key": {"product_id": {"N": str(int(item["product_id"]))}},
            "UpdateExpression": "ADD stock :q",
            "ExpressionAttributeValues": {":q": quantity},
        }
    }


def handler(event, _context):
    action = event["action"]
    order_id = event["order_id"]
    reserve = action == "reserve"
    items = event["items"]

    try:
        dynamodb.transact_write_items(
            TransactItems=[order_update(order_id, reserve)] + [stock_update(i, reserve) for i in items],
        )
    except dynamodb.exceptions.TransactionCanceledException as exc:
        codes = [r.get("Code") for r in exc.response.get("CancellationReasons", [])]
        if codes and codes[0] == "ConditionalCheckFailed":
            print(json.dumps({"order_id": order_id, "action": action, "result": "already_done"}))
            return {"order_id": order_id, "action": action}
        missing = [items[n - 1]["product_id"] for n, c in enumerate(codes) if n > 0 and c == "ConditionalCheckFailed"]
        if reserve and missing:
            log_metrics({"OutOfStock": (1, "Count")}, order_id=order_id, action=action, missing=missing)
            raise OutOfStock(f"Sin stock suficiente de los productos {missing}") from exc
        raise

    print(json.dumps({"order_id": order_id, "action": action, "result": "ok"}))
    return {"order_id": order_id, "action": action}
