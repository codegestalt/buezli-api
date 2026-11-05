# buezli-api

The official schema-driven Ruby client for the read-only
[Buezli API](https://buezli.app/api). Buezli is straightforward invoicing,
time tracking, and project management for small service teams. Learn more at
[buezli.app](https://buezli.app).

The gem builds its methods from a bundled, date-versioned API schema. It
supports records, expansions, delta polling, pagination, PDFs, and receipts.

## Install

```ruby
gem "buezli-api"
```

`buezli-api` requires Ruby 3.2 or newer.

## Quick start

```ruby
require "buezli/api"

client = Buezli::Api::Client.new(
  access_token: ENV.fetch("BUEZLI_API_TOKEN")
)

invoices = client.retrieve_invoices(limit: 50)
invoice = client.retrieve_invoice(123, expand: ["client"])

invoice.id
invoice.issue_date       # Date
invoice.updated_at       # Time
invoice.total            # { "cents" => 10810, "currency" => "CHF" }
invoice.client.name
invoice.line_items.first.description

account = client.retrieve_account  # the account the token reads
account.id
account.name
```

The default endpoint is `https://api.buezli.app`, and the newest bundled
schema is selected automatically. Pin an API version when needed:

```ruby
client = Buezli::Api::Client.new(
  access_token: ENV.fetch("BUEZLI_API_TOKEN"),
  version: "2026-07-14"
)
```

Schema-declared dates and timestamps become `Date` and `Time`. Decimal values
remain strings and money remains a `cents`/`currency` hash, avoiding precision
loss. Unknown record methods raise `NoMethodError`; declared but absent fields
return `nil`. Schema fields take precedence over client implementation details,
so an expanded `client` association is available as `record.client`. The
transport client used to build nested records is available separately as
`record.api_client`.

## Pagination and deltas

Collections are enumerable and retain the original query when paging:

```ruby
invoices = client.retrieve_invoices(
  updated_since: Time.utc(2026, 7, 14, 10),
  expand: ["client"],
  page: 1,
  limit: 100
)

invoices.each do |invoice|
  invoice.deleted? ? remove_local(invoice.id) : replace_local(invoice.to_h)
end

invoices.pagination
next_page = invoices.next_page
previous_page = next_page&.previous_page
```

## Downloads

```ruby
pdf = client.retrieve_invoice_pdf(123)
receipt = client.retrieve_expense_receipt(456)

pdf.body
pdf.filename
pdf.content_type
pdf.headers
```

Save a download when needed:

```ruby
File.binwrite(pdf.filename, pdf.body)
```

## Schema and errors

Inspect the selected API schema with `client.schema`, or fetch the schema
currently served by Buezli with `client.retrieve_schema`.

Failed requests raise `Buezli::Api::Client::Error`, exposing `status`, `code`,
`message`, `details`, `response_body`, and `headers`. Access tokens are never
included in errors or inspection output.

See the [API documentation](https://buezli.app/api) for available resources,
fields, expansions, and authentication.

## License

[MIT](LICENSE)
