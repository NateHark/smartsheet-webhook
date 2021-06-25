import hashlib
import hmac
import json
import logging
import secret
import smartsheet
import traceback

SMARTSHEET_CHALLENGE_HEADER = "Smartsheet-Hook-Challenge"
SMARTSHEET_CHALLENGE_RESPONSE_HEADER = "Smartsheet-Hook-Response"
SMARTSHEET_WEBHOOK_HMAC_HEADER = "Smartsheet-Hmac-SHA256"  

logger = logging.getLogger(__name__)


def handler(event, context):
    """ 
        The function invoked by Lambda when a request is received by the webhook callback URL defined in API Gateway
    """

    http_response = {
        "statusCode": 200
    }

    try:
        access_token = secret.get_secret(secret.SECRET_NAME_SMARTSHEET_ACCESS_TOKEN)
        smartsheet_client = smartsheet.Smartsheet(access_token=access_token)
        smartsheet_client.errors_as_exceptions(True)

        # The HTTP headers received with the webhook callback
        headers = event.get("headers")
        
        # The webhook callback URL will receive a request including a challenge header when creating a new webhook.
        # Return the value of the challenge header in a specific response header to validate the webhook.
        # See: https://smartsheet.redoc.ly/tag/webhooksDescription#section/Creating-a-Webhook/Webhook-Verification
        if SMARTSHEET_CHALLENGE_HEADER in headers:
            logger.info("Received webhook challenge. Sending challenge response.")
            http_response["headers"] = { SMARTSHEET_CHALLENGE_RESPONSE_HEADER: headers[SMARTSHEET_CHALLENGE_HEADER] }
            return http_response

        authorize_webhook(smartsheet_client, event["body"], headers[SMARTSHEET_WEBHOOK_HMAC_HEADER])        

        # Congratulations! You have successfully received and authorized your webhook callback. Now do something cool
        # with the data!
        
    except:
        logger.error("Unexpected failure processing webhook callback: {}".format(traceback.format_exc()))
        http_response["statusCode"] = 500
    
    return http_response

def authorize_webhook(smartsheet_client: smartsheet.Smartsheet, event_body: str, event_hmac: str):
    """
        Authorizes the webhook to validate that the webhook callback was initiated by Smartsheet and the payload
        has not been tampered with.
    """
    webhook_body = json.loads(event_body)
    webhook_id = webhook_body["webhookId"]
    shared_secret = get_webhook_shared_secret(smartsheet_client, webhook_id)
    calculated_hmac = hmac.new(bytes(shared_secret, 'UTF-8'), event_body.encode(), hashlib.sha256).hexdigest()
    if calculated_hmac != event_hmac:
        raise RuntimeError("Calculated HMAC {} did not match request signature {}".format(calculated_hmac, event_hmac)) 

def get_webhook_shared_secret(smartsheet_client: smartsheet.Smartsheet, webhook_id: int) -> str:
    """
        Fetches the shared secret for the webhook from Secrets Manager. If it does not exist, fetches the webhook
        via the Smartsheet API and stores the secret in Secrets Manager
    """
    shared_secret = secret.get_secret("{}/{}".format(secret.SECRET_PREFIX, webhook_id))
    if shared_secret is None:
        webhook = smartsheet_client.Webhooks.get_webhook(webhook_id)
        shared_secret = webhook.shared_secret
        secret.create_secret("{}/{}".format(secret.SECRET_PREFIX, webhook_id), shared_secret)
    return shared_secret