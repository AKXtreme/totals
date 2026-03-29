# Web Dashboard Response Guide

This is a short reference for the response shapes the local server returns to the web dashboard.

Base URL:

```text
http://<device-ip>:8080
```

API base:

```text
http://<device-ip>:8080/api
```

## General Notes

- Most API endpoints return JSON.
- Most handler errors return the same JSON error shape:

```json
{
  "error": true,
  "message": "Error description"
}
```

- `GET /health` is the main exception. It returns plain text:

```text
OK
```

- Transaction and summary responses are based on the app's filtered transaction set. Orphaned transactions are removed before those totals are returned.

## Dashboard-Facing Responses

### `GET /api/info`

Small server status payload.

```json
{
  "status": "running",
  "version": "1.0.0"
}
```

### `GET /api/accounts`

Returns an array of accounts already enriched with bank display data.

```json
[
  {
    "accountNumber": "1000123456789",
    "bank": 1,
    "bankName": "Commercial Bank of Ethiopia",
    "bankShortName": "CBE",
    "bankImage": "assets/images/cbe.png",
    "balance": 12500.0,
    "accountHolderName": "Eyob A.",
    "settledBalance": 12000.0,
    "pendingCredit": 500.0
  }
]
```

Fields:

- `accountNumber`: account identifier shown to the dashboard
- `bank`: numeric bank id
- `bankName`: full bank name
- `bankShortName`: short label used in UI
- `bankImage`: bank asset path
- `balance`: current balance
- `accountHolderName`: account holder display name
- `settledBalance`: nullable settled balance
- `pendingCredit`: nullable pending credit

### `GET /api/accounts/:bankId/:accountNumber`

Returns the same object shape as a single item from `/api/accounts`.

```json
{
  "accountNumber": "1000123456789",
  "bank": 1,
  "bankName": "Commercial Bank of Ethiopia",
  "bankShortName": "CBE",
  "bankImage": "assets/images/cbe.png",
  "balance": 12500.0,
  "accountHolderName": "Eyob A.",
  "settledBalance": 12000.0,
  "pendingCredit": 500.0
}
```

### `GET /api/shared-accounts`

Returns the quick-access/shared accounts saved from the Tools page.

```json
[
  {
    "id": 12,
    "accountNumber": "1000123456789",
    "bankId": 1,
    "bankName": "Commercial Bank of Ethiopia",
    "bankShortName": "CBE",
    "bankImage": "assets/images/cbe.png",
    "accountHolderName": "Eyob A.",
    "createdAt": "2026-03-29T12:00:00.000Z"
  }
]
```

Fields:

- `id`: nullable local database id
- `accountNumber`: shared account number
- `bankId`: numeric bank id
- `bankName`: full bank name
- `bankShortName`: short bank label
- `bankImage`: bank asset path
- `accountHolderName`: display name saved with the shared account
- `createdAt`: ISO datetime string

### `GET /api/shared-accounts/:bankId/:accountNumber`

Returns the same object shape as a single item from `/api/shared-accounts`.

```json
{
  "id": 12,
  "accountNumber": "1000123456789",
  "bankId": 1,
  "bankName": "Commercial Bank of Ethiopia",
  "bankShortName": "CBE",
  "bankImage": "assets/images/cbe.png",
  "accountHolderName": "Eyob A.",
  "createdAt": "2026-03-29T12:00:00.000Z"
}
```

### `POST /api/shared-accounts`

Creates a shared account and returns the same object shape as `GET /api/shared-accounts/:bankId/:accountNumber`.

```json
{
  "id": 12,
  "accountNumber": "1000123456789",
  "bankId": 1,
  "bankName": "Commercial Bank of Ethiopia",
  "bankShortName": "CBE",
  "bankImage": "assets/images/cbe.png",
  "accountHolderName": "Eyob A.",
  "createdAt": "2026-03-29T12:00:00.000Z"
}
```

### `DELETE /api/shared-accounts/:bankId/:accountNumber`

Delete confirmation payload.

```json
{
  "deleted": true,
  "bankId": 1,
  "accountNumber": "1000123456789"
}
```

### `GET /api/budgets`

Returns an array of budgets. If the dashboard sends `includeStatus=true`, each budget also includes a computed `status` object.

```json
[
  {
    "id": 3,
    "name": "April Essentials",
    "type": "category",
    "amount": 5000.0,
    "categoryId": 9,
    "categoryIds": [9, 10],
    "selectedCategoryIds": [9, 10],
    "startDate": "2026-04-01T00:00:00.000",
    "endDate": null,
    "rollover": false,
    "alertThreshold": 80.0,
    "isActive": true,
    "createdAt": "2026-03-29T12:00:00.000Z",
    "updatedAt": "2026-03-29T12:00:00.000Z",
    "timeFrame": "monthly",
    "appliesToAllExpenses": false,
    "categories": [
      {
        "id": 9,
        "name": "Rent",
        "essential": true,
        "flow": "expense",
        "typeLabel": "Essential"
      }
    ],
    "status": {
      "spent": 1500.0,
      "remaining": 3500.0,
      "percentageUsed": 30.0,
      "isExceeded": false,
      "isApproachingLimit": false,
      "periodStart": "2026-04-01T00:00:00.000",
      "periodEnd": "2026-04-30T23:59:59.000"
    }
  }
]
```

Fields:

- `id`: nullable budget id
- `name`: budget name
- `type`: `daily`, `monthly`, `yearly`, or `category`
- `amount`: configured budget amount
- `categoryId`: nullable primary category id
- `categoryIds`: nullable raw category id list
- `selectedCategoryIds`: normalized category ids used by the app
- `startDate`: ISO datetime string
- `endDate`: nullable ISO datetime string
- `rollover`: boolean rollover flag
- `alertThreshold`: numeric percentage threshold
- `isActive`: boolean active flag
- `createdAt`: ISO datetime string
- `updatedAt`: nullable ISO datetime string
- `timeFrame`: nullable category-budget recurrence value
- `appliesToAllExpenses`: true when the budget has no linked categories
- `categories`: resolved category objects for display
- `status`: optional computed spending state, present when `includeStatus=true`

Useful query params:

- `active`
- `type`
- `includeStatus`

### `GET /api/budgets/:id`

Returns the same object shape as a single item from `/api/budgets`.

### `POST /api/budgets`

Creates a budget and returns a single budget object. In the current implementation, the create response includes `status`.

```json
{
  "id": 3,
  "name": "April Essentials",
  "type": "category",
  "amount": 5000.0,
  "categoryId": 9,
  "categoryIds": [9, 10],
  "selectedCategoryIds": [9, 10],
  "startDate": "2026-04-01T00:00:00.000",
  "endDate": null,
  "rollover": false,
  "alertThreshold": 80.0,
  "isActive": true,
  "createdAt": "2026-03-29T12:00:00.000Z",
  "updatedAt": "2026-03-29T12:00:00.000Z",
  "timeFrame": "monthly",
  "appliesToAllExpenses": false,
  "categories": [
    {
      "id": 9,
      "name": "Rent",
      "essential": true,
      "flow": "expense",
      "typeLabel": "Essential"
    }
  ],
  "status": {
    "spent": 0.0,
    "remaining": 5000.0,
    "percentageUsed": 0.0,
    "isExceeded": false,
    "isApproachingLimit": false,
    "periodStart": "2026-04-01T00:00:00.000",
    "periodEnd": "2026-04-30T23:59:59.000"
  }
}
```

### `PUT /api/budgets/:id`

Updates a budget and returns the same single-budget shape as `POST /api/budgets`.

### `DELETE /api/budgets/:id`

Delete confirmation payload.

```json
{
  "deleted": true,
  "id": 3
}
```

### `GET /api/transactions`

Returns a paginated object, not a raw array.

```json
{
  "data": [
    {
      "amount": 850.0,
      "reference": "TXN-123",
      "creditor": "Acme Ltd",
      "receiver": null,
      "note": "Salary",
      "time": "2026-03-28T12:40:11.000",
      "status": "CLEARED",
      "currentBalance": "12500.00",
      "serviceCharge": null,
      "vat": null,
      "bankId": 1,
      "bankName": "CBE",
      "bankFullName": "Commercial Bank of Ethiopia",
      "bankImage": "assets/images/cbe.png",
      "type": "CREDIT",
      "transactionLink": null,
      "accountNumber": "1000123456789",
      "categoryId": 7
    }
  ],
  "total": 1,
  "limit": 20,
  "offset": 0
}
```

Fields inside each transaction:

- `amount`: numeric transaction amount
- `reference`: unique transaction reference
- `creditor`: nullable creditor/source label
- `receiver`: nullable receiver/destination label
- `note`: nullable free-text note
- `time`: nullable ISO datetime string
- `status`: nullable transaction status
- `currentBalance`: nullable balance string from the parsed message
- `serviceCharge`: nullable numeric charge
- `vat`: nullable numeric VAT
- `bankId`: nullable numeric bank id
- `bankName`: bank short name
- `bankFullName`: bank full name
- `bankImage`: bank asset path
- `type`: usually `CREDIT` or `DEBIT`
- `transactionLink`: nullable source link
- `accountNumber`: nullable account number
- `categoryId`: nullable category id

Query params the dashboard can use:

- `bankId`
- `accountNumber`
- `type`
- `status`
- `limit`
- `offset`
- `from`
- `to`

### `GET /api/transactions/stats`

Returns grouped transaction volume by bank.

```json
{
  "byAccount": [
    {
      "bankId": 1,
      "name": "CBE",
      "bankName": "Commercial Bank of Ethiopia",
      "volume": 152340.0,
      "count": 42
    }
  ],
  "totals": {
    "totalVolume": 152340.0,
    "totalCount": 42
  }
}
```

Note:

- `byAccount` is grouped by `bankId` in the current implementation, so each entry is effectively bank-level stats.

### `GET /api/summary`

Single totals object for the dashboard overview.

```json
{
  "totalBalance": 250000.0,
  "totalSettledBalance": 240000.0,
  "totalPendingCredit": 10000.0,
  "totalCredit": 95000.0,
  "totalDebit": 40000.0,
  "accountCount": 4,
  "bankCount": 3,
  "transactionCount": 182
}
```

### `GET /api/summary/by-bank`

Returns an array of bank summary cards.

```json
[
  {
    "bankId": 1,
    "bankName": "Commercial Bank of Ethiopia",
    "bankShortName": "CBE",
    "bankImage": "assets/images/cbe.png",
    "totalBalance": 150000.0,
    "settledBalance": 145000.0,
    "pendingCredit": 5000.0,
    "totalCredit": 65000.0,
    "totalDebit": 21000.0,
    "accountCount": 2,
    "transactionCount": 96
  }
]
```

### `GET /api/summary/by-account`

Returns an array of account-level summary cards.

```json
[
  {
    "accountNumber": "1000123456789",
    "accountHolderName": "Eyob A.",
    "bankId": 1,
    "bankName": "Commercial Bank of Ethiopia",
    "bankShortName": "CBE",
    "bankImage": "assets/images/cbe.png",
    "balance": 12500.0,
    "settledBalance": 12000.0,
    "pendingCredit": 500.0,
    "totalCredit": 32000.0,
    "totalDebit": 11000.0,
    "transactionCount": 28
  }
]
```

### `GET /api/categories`

Returns the category metadata the dashboard can use to resolve `categoryId` values from transactions and budgets.

```json
[
  {
    "id": 9,
    "name": "Rent",
    "essential": true,
    "uncategorized": false,
    "iconKey": "home",
    "colorKey": "red",
    "description": "Housing rent and lease payments",
    "flow": "expense",
    "recurring": true,
    "builtIn": true,
    "builtInKey": "expense_rent",
    "typeLabel": "Essential"
  }
]
```

Query params the dashboard can use:

- `flow`

### `GET /api/categories/:id`

Returns the same object shape as a single item from `/api/categories`.

### `GET /api/banks`

Returns the bank metadata the dashboard can use for labels, icons, and masking rules.

```json
[
  {
    "id": 1,
    "name": "Commercial Bank of Ethiopia",
    "shortName": "CBE",
    "codes": ["CBE"],
    "image": "assets/images/cbe.png",
    "maskPattern": 4,
    "uniformMasking": true,
    "simBased": false
  }
]
```

### `GET /api/banks/:id`

Returns the same bank shape as a single item from `/api/banks`.

```json
{
  "id": 1,
  "name": "Commercial Bank of Ethiopia",
  "shortName": "CBE",
  "codes": ["CBE"],
  "image": "assets/images/cbe.png",
  "maskPattern": 4,
  "uniformMasking": true,
  "simBased": false
}
```

### `GET /api/random`

Simple utility payload.

```json
{
  "number": 1234,
  "timestamp": "2026-03-29T10:22:11.000"
}
```

### `POST /api/random/generate`

Same response shape as `GET /api/random`, but generates a new number first.

```json
{
  "number": 5678,
  "timestamp": "2026-03-29T10:22:15.000"
}
```

## Quick Integration Notes

- Arrays are returned directly for `accounts`, `shared-accounts`, `budgets`, `categories`, `banks`, `summary/by-bank`, and `summary/by-account`.
- `transactions` is the main wrapped response and includes pagination metadata.
- `summary`, `random`, and mutation delete endpoints return single JSON objects.
- Budget `status` is optional on `GET` requests and is included when the request asks for `includeStatus=true`.
- Budget `POST` and `PUT` responses currently include `status`.
- Numeric totals are returned as JSON numbers.
- Some balance-like source values such as `currentBalance` are returned as strings because they come from parsed transaction messages.
- If the dashboard needs strict typing, nullable fields should be treated as optional in the frontend model.
