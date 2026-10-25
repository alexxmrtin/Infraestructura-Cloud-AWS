import json
import os

import boto3

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]

sfn = boto3.client("stepfunctions")


def handler(event, _context):
    failures = []
    for record in event["Records"]:
        try:
            order = json.loads(record["body"])
            sfn.start_execution(
                stateMachineArn=STATE_MACHINE_ARN,
                name=order["order_id"],
                input=json.dumps(order),
            )
            print(json.dumps({"order_id": order["order_id"], "result": "started"}))
        except sfn.exceptions.ExecutionAlreadyExists:
            print(json.dumps({"order_id": order["order_id"], "result": "already_started"}))
        except Exception as exc:
            print(json.dumps({"message_id": record["messageId"], "error": repr(exc)}))
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}
