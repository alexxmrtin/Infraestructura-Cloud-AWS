import json
import os

import boto3

STOCK_TABLE = os.environ["STOCK_TABLE"]
MAX_STOCK = 100000

stock = boto3.resource("dynamodb").Table(STOCK_TABLE)


def response(status, body):
    return {"statusCode": status, "headers": {"Content-Type": "application/json"}, "body": json.dumps(body)}


def list_stock():
    items = stock.scan()["Items"]
    products = sorted(({"product_id": int(i["product_id"]), "stock": int(i["stock"])} for i in items), key=lambda p: p["product_id"])
    return response(200, {"products": products})


def set_stock(raw_product_id, raw_body):
    try:
        product_id = int(raw_product_id)
        new_stock = json.loads(raw_body or "{}")["stock"]
    except (ValueError, KeyError, TypeError):
        return response(400, {"error": 'Manda {"stock": <numero>} y un product_id numerico'})
    if product_id <= 0 or not isinstance(new_stock, int) or isinstance(new_stock, bool) or not 0 <= new_stock <= MAX_STOCK:
        return response(400, {"error": f"stock tiene que ser un entero entre 0 y {MAX_STOCK}"})

    stock.put_item(Item={"product_id": product_id, "stock": new_stock})
    return response(200, {"product_id": product_id, "stock": new_stock})


def handler(event, _context):
    method = event["httpMethod"]
    resource = event["resource"]
    print(json.dumps({"method": method, "resource": resource, "api_key_id": event["requestContext"]["identity"].get("apiKeyId")}))

    if method == "GET" and resource == "/stock":
        return list_stock()
    if method == "PUT" and resource == "/stock/{product_id}":
        return set_stock(event["pathParameters"]["product_id"], event.get("body"))
    return response(404, {"error": "Ruta no encontrada"})
