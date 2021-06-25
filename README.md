# smartsheet-webhook
A somewhat minimal serverless handler for Smartsheet webhooks using AWS API Gateway and demonstrating good practices for secret storage and callback authentication.

For more information see my [blog post](https://nathanharkenrider.com/posts/smartsheet-webhook-callbacks-with-api-gateway/) on this topic.

# Deployment

## Prerequisites
The following prerequisites are required. Installation and/or configuration is out of scope of this README.

*Note*: Running the Terraform in this tutorial will incur at least $0.80 USD monthly in AWS fees due to the use of Secrets Manager. To avoid this cost on a recurring basis, remember to run `terraform destroy` when you're finished.

* [AWS account credentials](https://aws.amazon.com)
* [Smartsheet developer account](https://developers.smartsheet.com/register/)
* [Terraform](https://www.terraform.io/downloads.html)
* Python 3.8+

# Create the required infrastructure in AWS
```bash
# Clone this repository
$ git clone https://github.com/NateHark/smartsheet-webhook

# Build the Lambda package
$ cd smartsheet-webhook
$ ./package.sh

# Create AWS infrastructure via Terraform
# Note the value of the api_gateway_endpoint for use in subsequent steps
$ export TF_VAR_smartsheet_access_token=<access_token>
$ terraform apply

```

# Create a test sheet
```bash
# Create an empty sheet that will act as your webhook trigger.
# Note the sheet id returned in the response for use in subsequent steps.
$ curl https://api.smartsheet.com/2.0/sheets \
-H "Authorization: Bearer <access_token>" \
-H "Content-Type: application/json" \
-X POST \
-d '{"name":"Demo Sheet","columns":[{"title":"Primary Column", "primary":true,"type":"TEXT_NUMBER"}]}'

```

# Create a new webhook
```bash
# Create a webhook using the API Gateway URL and sheet id obtained in prior steps. 
$ curl https://api.smartsheet.com/2.0/webhooks \
-H "Authorization: Bearer <access_token>" \
-H "Content-Type: application/json" \
-X POST \
-d '{"name": "Demo Webhook", "callbackUrl": "<api_gateway_endpoint>/webhook", "scope": "sheet", "scopeObjectId": <sheet_id>, "events": ["*.*"], "version": 1}'
```

# Enable the webhook
```bash
# Enable the webhook. This will trigger webhook verification via the Smartsheet API
$ curl https://api.smartsheet.com/2.0/webhooks/<webhook_id> \
-H "Authorization: Bearer <access_token>" \
-H "Content-Type: application/json" \
-X PUT \
-d '{ "enabled": true }
```

# Check webhook status
```bash
# Check the status of the webhook. If everything is working, the `status` field should have the value `ENABLED`.
$ curl -H "Authorization: Bearer <access_token>" https://api.smartsheet.com/2.0/webhooks/<webhook_id> 
```