import json
import os
from decimal import Decimal

import boto3

INVOICES_BUCKET = os.environ["INVOICES_BUCKET"]

s3 = boto3.client("s3")


def pdf_text(value):
    return value.encode("latin-1", "replace").decode("latin-1").replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def build_pdf(lines):
    content = ["BT", "/F1 12 Tf", "50 800 Td", "16 TL"]
    content += [f"({pdf_text(line)}) Tj T*" for line in lines]
    content.append("ET")
    stream = "\n".join(content).encode("latin-1")

    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
    ]

    pdf = b"%PDF-1.4\n"
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(pdf))
        pdf += f"{number} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(pdf)
    pdf += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
    pdf += b"".join(f"{offset:010d} 00000 n \n".encode() for offset in offsets)
    pdf += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return pdf


def handler(event, _context):
    order_id = event["order_id"]
    lines = [
        "ShopFlow - Factura",
        "",
        f"Pedido: {order_id}",
        f"Fecha: {event['created_at'][:19].replace('T', ' ')} UTC",
        f"Cliente: {event.get('email') or event['user_id']}",
        f"Pago: {event['payment']['payment_id']}",
        "",
    ]
    for item in event["items"]:
        subtotal = Decimal(item["price"]) * int(item["quantity"])
        lines.append(f"{item['quantity']} x {item['name']} ({item['price']} EUR) = {subtotal:.2f} EUR")
    lines += ["", f"Total: {event['total']} EUR"]

    key = f"{event['user_id']}/{order_id}.pdf"
    s3.put_object(Bucket=INVOICES_BUCKET, Key=key, Body=build_pdf(lines), ContentType="application/pdf")
    print(json.dumps({"order_id": order_id, "invoice": f"s3://{INVOICES_BUCKET}/{key}"}))
    return {"key": key}
