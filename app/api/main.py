import json
import os
import socket
import time
import urllib.request
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from decimal import Decimal
from functools import lru_cache

import boto3
import jwt
from boto3.dynamodb.conditions import Key
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
import psycopg
import redis
from fastapi import Depends, FastAPI, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field

DB_CONNINFO = {
    "host": os.environ["DB_HOST"],
    "port": int(os.environ.get("DB_PORT", "5432")),
    "dbname": os.environ["DB_NAME"],
    "user": os.environ["DB_USER"],
    "password": os.environ["DB_PASSWORD"],
    "sslmode": "require",
    "connect_timeout": 5,
}
CACHE_HOST = os.environ.get("CACHE_HOST") or None
CACHE_TTL_SECONDS = int(os.environ.get("CACHE_TTL_SECONDS", "60"))
CARTS_TABLE = os.environ["CARTS_TABLE"]
CART_TTL_SECONDS = int(os.environ.get("CART_TTL_SECONDS", "86400"))
COGNITO_ISSUER = (
    f"https://cognito-idp.{os.environ['AWS_REGION']}.amazonaws.com/{os.environ['COGNITO_USER_POOL_ID']}"
)
COGNITO_CLIENT_ID = os.environ["COGNITO_CLIENT_ID"]
ORDERS_TABLE = os.environ["ORDERS_TABLE"]
STOCK_TABLE = os.environ["STOCK_TABLE"]
ORDERS_TOPIC_ARN = os.environ["ORDERS_TOPIC_ARN"]
INVOICES_BUCKET = os.environ["INVOICES_BUCKET"]
INVOICE_LINK_SECONDS = 300

SEED_PRODUCTS = [
    ("Camiseta ShopFlow", Decimal("19.90")),
    ("Taza de cafe", Decimal("9.50")),
    ("Sudadera con capucha", Decimal("39.00")),
    ("Pegatinas (pack de 10)", Decimal("4.99")),
    ("Gorra", Decimal("14.00")),
]

dynamodb = boto3.resource("dynamodb")
carts = dynamodb.Table(CARTS_TABLE)
orders = dynamodb.Table(ORDERS_TABLE)
sns = boto3.client("sns")
s3 = boto3.client("s3", config=Config(signature_version="s3v4"))
cognito = boto3.client("cognito-idp")
cache = (
    redis.Redis(host=CACHE_HOST, port=6379, ssl=True, socket_timeout=1, socket_connect_timeout=1, decode_responses=True)
    if CACHE_HOST
    else None
)

jwks = jwt.PyJWKClient(f"{COGNITO_ISSUER}/.well-known/jwks.json", cache_keys=True, timeout=5)
bearer = HTTPBearer(auto_error=False)


def db():
    return psycopg.connect(**DB_CONNINFO)


def create_schema():
    with db() as conn:
        conn.execute("SELECT pg_advisory_xact_lock(4242)")
        conn.execute(
            "CREATE TABLE IF NOT EXISTS products ("
            " id SERIAL PRIMARY KEY,"
            " name TEXT NOT NULL,"
            " price NUMERIC(10, 2) NOT NULL)"
        )
        if conn.execute("SELECT count(*) FROM products").fetchone()[0] == 0:
            with conn.cursor() as cur:
                cur.executemany("INSERT INTO products (name, price) VALUES (%s, %s)", SEED_PRODUCTS)


@asynccontextmanager
async def lifespan(_app):
    create_schema()
    yield


app = FastAPI(title="ShopFlow API", lifespan=lifespan)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/api/info")
def info():
    data = {"task": socket.gethostname(), "availability_zone": None}
    metadata_uri = os.environ.get("ECS_CONTAINER_METADATA_URI_V4")
    if metadata_uri:
        try:
            with urllib.request.urlopen(f"{metadata_uri}/task", timeout=1) as resp:
                data["availability_zone"] = json.load(resp).get("AvailabilityZone")
        except OSError:
            pass
    return data


@app.get("/api/products")
def list_products():
    if cache:
        try:
            cached = cache.get("products")
            if cached:
                return {"source": "cache", "products": with_stock(json.loads(cached))}
        except redis.RedisError:
            pass

    try:
        with db() as conn:
            rows = conn.execute("SELECT id, name, price FROM products ORDER BY id").fetchall()
    except psycopg.Error as exc:
        raise HTTPException(status_code=503, detail="Base de datos no disponible") from exc

    products = [{"id": r[0], "name": r[1], "price": float(r[2])} for r in rows]

    if cache:
        try:
            cache.set("products", json.dumps(products), ex=CACHE_TTL_SECONDS)
        except redis.RedisError:
            pass

    return {"source": "database", "products": with_stock(products)}


def with_stock(products):
    if not products:
        return products
    try:
        response = dynamodb.batch_get_item(
            RequestItems={STOCK_TABLE: {"Keys": [{"product_id": p["id"]} for p in products]}}
        )
        stock = {int(i["product_id"]): int(i["stock"]) for i in response["Responses"][STOCK_TABLE]}
    except (BotoCoreError, ClientError):
        stock = {}
    return [{**p, "stock": stock.get(p["id"])} for p in products]


def current_user(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)) -> dict:
    if credentials is None:
        raise HTTPException(status_code=401, detail="Falta el token", headers={"WWW-Authenticate": "Bearer"})
    try:
        key = jwks.get_signing_key_from_jwt(credentials.credentials)
        claims = jwt.decode(
            credentials.credentials,
            key.key,
            algorithms=["RS256"],
            issuer=COGNITO_ISSUER,
            options={"require": ["exp", "iss", "sub", "token_use", "client_id"]},
        )
    except jwt.PyJWKClientConnectionError as exc:
        raise HTTPException(status_code=503, detail="Cognito no disponible") from exc
    except jwt.PyJWTError as exc:
        raise HTTPException(status_code=401, detail="Token no valido", headers={"WWW-Authenticate": "Bearer"}) from exc
    if claims["token_use"] != "access" or claims["client_id"] != COGNITO_CLIENT_ID:
        raise HTTPException(status_code=401, detail="Token no valido", headers={"WWW-Authenticate": "Bearer"})
    return claims


@lru_cache(maxsize=1024)
def user_email(username: str) -> str:
    try:
        attributes = cognito.admin_get_user(UserPoolId=os.environ["COGNITO_USER_POOL_ID"], Username=username)["UserAttributes"]
    except (BotoCoreError, ClientError):
        return username
    return next((a["Value"] for a in attributes if a["Name"] == "email"), username)


@app.get("/api/me")
def me(user: dict = Depends(current_user)):
    return {"user_id": user["sub"], "username": user.get("username")}


class CartItem(BaseModel):
    product_id: int = Field(gt=0)
    quantity: int = Field(gt=0, le=100)


class Cart(BaseModel):
    items: list[CartItem]


@app.get("/api/cart")
def get_cart(user: dict = Depends(current_user)):
    item = carts.get_item(Key={"user_id": user["sub"]}).get("Item")
    if not item:
        raise HTTPException(status_code=404, detail="Carrito vacio")
    return {
        "items": [{"product_id": int(i["product_id"]), "quantity": int(i["quantity"])} for i in item["items"]],
        "expires_at": int(item["expires_at"]),
    }


@app.put("/api/cart")
def put_cart(cart: Cart, user: dict = Depends(current_user)):
    expires_at = int(time.time()) + CART_TTL_SECONDS
    items = [i.model_dump() for i in cart.items]
    carts.put_item(
        Item={"user_id": user["sub"], "email": user_email(user["username"]), "items": items, "expires_at": expires_at}
    )
    return {"items": items, "expires_at": expires_at}


@app.delete("/api/cart", status_code=204)
def delete_cart(user: dict = Depends(current_user)):
    carts.delete_item(Key={"user_id": user["sub"]})


def order_view(item):
    return {
        "order_id": item["order_id"],
        "status": item["status"],
        "total": item["total"],
        "created_at": item["created_at"],
        "items": [{"name": i["name"], "quantity": int(i["quantity"])} for i in item["items"]],
        "failure_reason": item.get("failure_reason"),
        "has_invoice": "invoice_key" in item,
    }


@app.post("/api/orders", status_code=202)
def create_order(user: dict = Depends(current_user)):
    cart = carts.get_item(Key={"user_id": user["sub"]}).get("Item")
    if not cart or not cart["items"]:
        raise HTTPException(status_code=400, detail="El carrito esta vacio")

    quantities = {int(i["product_id"]): int(i["quantity"]) for i in cart["items"]}
    try:
        with db() as conn:
            rows = conn.execute(
                "SELECT id, name, price FROM products WHERE id = ANY(%s)", (list(quantities),)
            ).fetchall()
    except psycopg.Error as exc:
        raise HTTPException(status_code=503, detail="Base de datos no disponible") from exc
    if len(rows) != len(quantities):
        raise HTTPException(status_code=400, detail="El carrito tiene productos que ya no existen")

    items = [
        {"product_id": r[0], "name": r[1], "price": f"{r[2]:.2f}", "quantity": quantities[r[0]]}
        for r in sorted(rows)
    ]
    order = {
        "order_id": str(uuid.uuid4()),
        "user_id": user["sub"],
        "email": user_email(user["username"]),
        "items": items,
        "total": f"{sum(r[2] * quantities[r[0]] for r in rows):.2f}",
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }

    orders.put_item(Item={**order, "status": "PENDING"})
    try:
        sns.publish(TopicArn=ORDERS_TOPIC_ARN, Message=json.dumps(order))
    except (BotoCoreError, ClientError) as exc:
        orders.update_item(
            Key={"order_id": order["order_id"]},
            UpdateExpression="SET #s = :s, failure_reason = :r",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":s": "FAILED", ":r": "NotPublished"},
        )
        raise HTTPException(status_code=503, detail="No se ha podido enviar el pedido") from exc

    carts.delete_item(Key={"user_id": user["sub"]})
    return {"order_id": order["order_id"], "status": "PENDING", "total": order["total"]}


@app.get("/api/orders")
def list_orders(user: dict = Depends(current_user)):
    response = orders.query(
        IndexName="by_user",
        KeyConditionExpression=Key("user_id").eq(user["sub"]),
        ScanIndexForward=False,
        Limit=10,
    )
    return {"orders": [order_view(i) for i in response["Items"]]}


@app.get("/api/orders/{order_id}/invoice")
def invoice_link(order_id: str, user: dict = Depends(current_user)):
    item = orders.get_item(Key={"order_id": order_id}).get("Item")
    if not item or item["user_id"] != user["sub"]:
        raise HTTPException(status_code=404, detail="Pedido no encontrado")
    if "invoice_key" not in item:
        raise HTTPException(status_code=409, detail="La factura todavia no esta lista")
    url = s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": INVOICES_BUCKET, "Key": item["invoice_key"]},
        ExpiresIn=INVOICE_LINK_SECONDS,
    )
    return {"url": url, "expires_in": INVOICE_LINK_SECONDS}
