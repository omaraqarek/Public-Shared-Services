# Shared Services Integration Hub

Welcome to the **Shared Services Integration Hub** documentation. This repository provides the PL/SQL SDK and guidelines for internal systems to easily communicate with external providers (such as EDAAT) through a centralized, secure Hub.

## Table of Contents
- [Architecture & Data Flow](#architecture--data-flow)
- [Installation](#installation)
- [How to Use the SDK](#how-to-use-the-sdk)
- [JSON Payload Structure](#json-payload-structure)
- [Flow Types & Examples](#flow-types--examples)
  - [Synchronous (SYNC) Flow](#1-synchronous-sync-flow)
  - [Asynchronous (ASYNC) Flow](#2-asynchronous-async-flow)

---

## Architecture & Data Flow

The Integration Hub acts as a secure proxy and payload orchestrator between internal Oracle systems and external third-party APIs. 

**The Data Flow:**
1. **Authentication**: The internal system requests an OAuth2 token from the Hub (`/hub/security/token`) using Client ID, Client Secret, System Code, and Environment Type headers.
2. **Execution**: The internal system invokes the Hub's runtime endpoint (`/hub/runtime/execute`) using the PL/SQL SDK, passing the acquired token and a standard JSON payload.
3. **Orchestration**: The Hub parses the request, identifies the provider (e.g., EDAAT), dynamically injects the necessary external API tokens, logs the transaction, and forwards the request.
4. **Response**: The Hub receives the external provider's response, logs the outcome, and returns the response back to the internal system.

---

## Installation

1. Deploy the SDK package `hub_client_sdk_pkg.sql` into your internal Oracle APEX / Database environment.
2. **(Important)** Ensure your internal environment has the necessary Oracle Wallet and ACL configurations to make outbound HTTPS requests to the Hub ORDS endpoints.
3. Review the `execute_with_auth` function in the package body. A commented block is provided where you can integrate your own local token caching logic (e.g., storing the token in a local table) to prevent redundant authentication calls. The underlying `get_auth_token` function now returns `expires_in` (a `TIMESTAMP` indicating exactly when the token expires) as an `OUT` parameter, which you can use to effectively manage your local cache validity.

---

## How to Use the SDK

The SDK simplifies the process by combining authentication and execution into a single call. 

```sql
DECLARE
    l_request_json CLOB;
    l_response     CLOB;
BEGIN
    -- 1. Construct your JSON payload
    l_request_json := '{ ... }';

    -- 2. Execute via the SDK
    l_response := hub_client_sdk_pkg.execute_with_auth(
        p_hub_base_url  => 'https://your-ords-domain.com/ords/hub_schema',
        p_client_id     => 'your_client_id',
        p_client_secret => 'your_client_secret',
        p_request_json  => l_request_json
    );

    -- 3. Process the Hub's response
    dbms_output.put_line(l_response);
END;
```

---

## JSON Payload Structure

Every request sent to the Hub must follow a strict unified JSON structure. Here is what each key represents:

| Key | Type | Description |
| :--- | :--- | :--- |
| `system_code` | String | Unique identifier for your internal system (e.g., `"AQAREK"`). Matches your Hub registration. |
| `environment` | String | Target environment. Usually `"TEST"` or `"LIVE"`. |
| `flow_type` | String | Execution model: `"SYNC"` (Synchronous) or `"ASYNC"` (Asynchronous). |
| `provider_code` | String | Target external provider code configured in the Hub (e.g., `"EDAAT"`, `"HYPER_PAY"`, `"UNIFONIC"`, `"BRANCH"`, `"ELM"`). |
| `end_point` | String | The specific provider URI path you are calling (e.g., `"/api/v1/Invoices/SingleWithClient"`). |
| `http_method` | String | The HTTP method to use for the external call (e.g., `"POST"`, `"GET"`, `"PUT"`). |
| `request_details` | Array | Array of request detail objects. |
| `request_details[].internal_code` | String | Caller provided internal reference code. |
| `request_details[].headers` | Array | Custom HTTP headers to pass to the provider. (Do NOT include Auth headers, the Hub handles this). |
| `request_details[].query_params`| Array | URL Query parameters. Example: `[{"name": "id", "value": "123"}]`. |
| `request_details[].body` | Object | The exact JSON body structure expected by the external provider. |

---

## Sample Payloads

Sample JSON request templates for various supported providers have been included in this repository under the `samples/` directory:

- [request_schema.json](./samples/request_schema.json): The base schema validation structure.
- [sample_request_branch.json](./samples/sample_request_branch.json): Example for Branch provider.
- [sample_request_edaat.json](./samples/sample_request_edaat.json): Example for Edaat provider.
- [sample_request_elm.json](./samples/sample_request_elm.json): Example for Elm provider.
- [sample_request_hyperpay.json](./samples/sample_request_hyperpay.json): Example for HyperPay provider.
- [sample_request_unifonic.json](./samples/sample_request_unifonic.json): Example for Unifonic provider.

---

## Flow Types & Examples

### 1. Synchronous (SYNC) Flow

In a **SYNC** flow, your PL/SQL session waits until the Hub has contacted the external provider and received a final response. This is ideal for lightweight, immediate actions.

**Request Example:**
```json
{
  "system_code": "AQAREK",
  "environment": "TEST",
  "flow_type": "SYNC",
  "provider_code": "EDAAT",
  "end_point": "/api/v1/Invoices/SingleWithClient",
  "http_method": "POST",
  "request_details": [
    {
      "internal_code": "AQAREK#85265489",
      "headers": [{"name": "Content-Type", "value": "application/json", "seq": 1}],
      "query_params": [],
      "body": {
        "IsClientEnterpise": false,
        "NationalId": "213584745789654",
        "InternalCode": "AQAREK#85265489",
        "IssueDate": "2026-06-15",
        "DueDate": "2026-06-15",
        "TotalAmount": 12500,
        "Products": [
          {
            "ProductId": 10001,
            "Price": 12500,
            "Qty": 1
          }
        ],
        "ExportToSadad": true,
        "HasValidityPeriod": true,
        "FromDurationTime": "00:00",
        "ToDurationTime": "18:00",
        "ExpiryDate": "2026-12-31"
      }
    }
  ]
}
```

**Response Example:**
The response will be the direct JSON response from the provider. 

*JSON Response Body:*
```json
{
  "status": "Success",
  "invoiceNo": "INV-85265489"
}
```

### 2. Asynchronous (ASYNC) Flow

In an **ASYNC** flow, the Hub validates the payload, generates a tracking ID, and immediately returns it to your system. The Hub then forwards the payload to the provider in a background job. This is ideal for long-running reports or heavy processing where your application shouldn't block.

**Request Example:**
```json
{
  "system_code": "AQAREK",
  "environment": "TEST",
  "flow_type": "ASYNC",
  "provider_code": "EDAAT",
  "end_point": "/api/v1/Invoices/SingleWithClient",
  "http_method": "POST",
  "request_details": [
    {
      "internal_code": "AQAREK#85265489",
      "headers": [{"name": "Content-Type", "value": "application/json", "seq": 1}],
      "query_params": [],
      "body": {
        "IsClientEnterpise": false,
        "NationalId": "213584745789654",
        "InternalCode": "AQAREK#85265489",
        "IssueDate": "2026-06-15",
        "DueDate": "2026-06-15",
        "TotalAmount": 12500,
        "Products": [
          {
            "ProductId": 10001,
            "Price": 12500,
            "Qty": 1
          }
        ],
        "ExportToSadad": true,
        "HasValidityPeriod": true,
        "FromDurationTime": "00:00",
        "ToDurationTime": "18:00",
        "ExpiryDate": "2026-12-31"
      }
    }
  ]
}
```

**Response Example:**
The Hub returns an acknowledgment immediately with the tracking UUIDs for each request detail object. You will use the `transactionUuid` to track the status later.
```json
[
  {
    "internal_code": "AQAREK#85265489",
    "transactionUuid": "A1B2C3D4E5F678901234567890ABCDEF",
    "status": "QUEUED"
  }
]
```

### 3. Check Transaction Status API

This endpoint retrieves the status of a specific integration transaction by its tracking UUID. It is useful for tracking the status of **ASYNC** flows.

**Endpoint:** 
`GET /hub/runtime/transactionStatus/{uuid}`

**Path Parameters:**
- `uuid`: The `transactionUuid` returned in the ASYNC flow acknowledgment.

**Response Example:**
```json
{
  "transaction_uuid": "A1B2C3D4E5F678901234567890ABCDEF",
  "flow_type": "ASYNC",
  "status": "COMPLETED",
  "end_point": "/api/v1/Invoices/SingleWithClient",
  "request_payload": { ... },
  "response_payload": { ... },
  "http_status_code": 200,
  "error_message": null,
  "created_at": "2026-06-17T12:00:00Z",
  "completed_at": "2026-06-17T12:00:05Z",
  "notification_sent": "Y"
}
```

### 4. Asynchronous (ASYNC) Callback / Webhook

When an **ASYNC** request finishes processing (either successfully or with an error), the Hub will push a notification to the `callback_url` registered for your system's environment.

**Method:** `POST`
**Content-Type:** `application/json`

**Callback JSON Payload Example:**
The payload is a JSON array containing the execution results of your asynchronous requests.

```json
[
  {
    "internal_code": "AQAREK#85265489",
    "transactionUuid": "A1B2C3D4E5F678901234567890ABCDEF",
    "status": "COMPLETED",
    "httpStatusCode": 200,
    "responsePayload": {
      "status": "Success",
      "invoiceNo": "INV-85265489"
    },
    "errorMessage": null
  }
]
```
