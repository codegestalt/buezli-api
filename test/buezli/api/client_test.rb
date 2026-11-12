require "test_helper"
require "socket"

class Buezli::Api::ClientTest < ActiveSupport::TestCase
  test "defines retrieval methods from schema endpoints" do
    client = Buezli::Api::Client.new(access_token: "secret", endpoint: "https://api.test", schema: example_schema)

    assert_respond_to client, :retrieve_events
    assert_respond_to client, :retrieve_event
    assert_respond_to client, :retrieve_event_pdf
    assert_respond_to client, :retrieve_schema
    assert_not_respond_to client, :retrieve_event_parts
  end

  test "builds typed records and nested associations from schema declarations" do
    client = Buezli::Api::Client.new(access_token: "secret", endpoint: "https://api.test", schema: example_schema)
    event = client.build_record("Event", {
      id: 12,
      occurred_on: "2026-07-14",
      updated_at: "2026-07-14T10:00:00Z",
      amount: { cents: 16_000, currency: "CHF" },
      ratio: "1.25",
      event_parts: [
        { id: 4, starts_at: "2026-07-14T11:00:00Z" }
      ]
    })

    assert_equal 12, event.id
    assert_equal Date.new(2026, 7, 14), event.occurred_on
    assert_equal Time.utc(2026, 7, 14, 10), event.updated_at
    assert_equal({ "cents" => 16_000, "currency" => "CHF" }, event.amount)
    assert_equal "1.25", event.ratio
    assert_equal 4, event.event_parts.first.id
    assert_equal Time.utc(2026, 7, 14, 11), event.event_parts.first.starts_at
    assert_nil event.organizer
    assert_respond_to event, :organizer
    assert_raises(NoMethodError) { event.typo }
  end

  test "schema client associations are not shadowed by the API client" do
    api_client = Buezli::Api::Client.new(access_token: "secret")
    time_entry = api_client.build_record("TimeEntry", {
      id: 12,
      client: { id: 7, name: "Example AG" }
    })

    assert_equal "Example AG", time_entry.client.name
    assert_same api_client, time_entry.api_client
  end

  test "represents delta tombstones as deleted records" do
    client = Buezli::Api::Client.new(access_token: "secret", endpoint: "https://api.test", schema: example_schema)
    tombstone = client.build_record("Event", {
      id: 12,
      _deleted: true,
      updated_at: "2026-07-14T10:00:00Z"
    })

    assert_predicate tombstone, :deleted?
    assert_equal true, tombstone[:_deleted]
    assert_equal 12, tombstone.to_h["id"]
    assert_nil tombstone.occurred_on
  end

  test "retrieves collections with authentication, query parameters, and pagination" do
    first_page = {
      data: [
        {
          id: 12,
          occurred_on: "2026-07-14",
          updated_at: "2026-07-14T10:00:00Z",
          organizer: { id: 7 }
        }
      ],
      meta: {
        pagination: { page: 1, limit: 1, count: 2, pages: 2, next: 2, prev: nil }
      }
    }
    second_page = {
      data: [
        { id: 13, occurred_on: "2026-07-15", updated_at: "2026-07-15T10:00:00Z" }
      ],
      meta: {
        pagination: { page: 2, limit: 1, count: 2, pages: 2, next: nil, prev: 1 }
      }
    }
    server = LocalApiServer.new(json_response(first_page), json_response(second_page), json_response(first_page))
    params = {
      expand: [ "organizer" ],
      updated_since: Time.utc(2026, 7, 14, 9),
      page: 1,
      limit: 1
    }
    client = Buezli::Api::Client.new(
      access_token: "secret",
      endpoint: server.endpoint,
      host: "api.buezli.test:#{server.port}",
      schema: example_schema
    )

    events = client.retrieve_events(**params)
    next_events = events.next_page
    previous_events = next_events.previous_page
    server.finish

    assert_instance_of Buezli::Api::Client::List, events
    assert_equal [ 12 ], events.map(&:id)
    assert_equal 7, events.first.organizer.id
    assert_equal 2, events.pagination["next"]
    assert_equal [ 13 ], next_events.map(&:id)
    assert_nil next_events.next_page
    assert_equal 1, next_events.pagination["prev"]
    assert_equal [ 12 ], previous_events.map(&:id)
    assert_equal [ "organizer" ], params[:expand]
    assert_equal Time.utc(2026, 7, 14, 9), params[:updated_since]

    first_request, second_request, third_request = server.requests
    assert_equal "Bearer secret", first_request.headers.fetch("authorization")
    assert_equal "api.buezli.test:#{server.port}", first_request.headers.fetch("host")
    assert_equal "/2026-07-14/events", first_request.path
    assert_equal(
      {
        "expand[]" => [ "organizer" ],
        "updated_since" => [ "2026-07-14T09:00:00Z" ],
        "page" => [ "1" ],
        "limit" => [ "1" ]
      },
      first_request.query
    )
    assert_equal [ "2" ], second_request.query.fetch("page")
    assert_equal [ "organizer" ], second_request.query.fetch("expand[]")
    assert_equal [ "2026-07-14T09:00:00Z" ], second_request.query.fetch("updated_since")
    assert_equal [ "1" ], third_request.query.fetch("page")
  ensure
    server&.close
  end

  test "stops pagination when the server repeats the current page" do
    payload = {
      data: [],
      meta: {
        pagination: { page: 2, limit: 1, count: 2, pages: 2, next: 2, prev: 1 }
      }
    }
    server = LocalApiServer.new(json_response(payload), json_response(payload))
    client = Buezli::Api::Client.new(access_token: "secret", endpoint: server.endpoint, schema: example_schema)

    events = client.retrieve_events
    error = assert_raises(Buezli::Api::Client::Error) { events.next_page }

    assert_equal "Infinite pagination loop detected", error.message
  ensure
    server&.close
  end

  test "returns binary endpoint responses as downloads with metadata" do
    server = LocalApiServer.new(
      LocalApiServer::Response.new(
        status: 200,
        headers: {
          "Content-Type" => "application/pdf",
          "Content-Disposition" => 'attachment; filename="event-12.pdf"',
          "X-Request-Id" => "request-123"
        },
        body: "%PDF-example"
      )
    )
    client = Buezli::Api::Client.new(access_token: "secret", endpoint: server.endpoint, schema: example_schema)

    download = client.retrieve_event_pdf(12)
    server.finish

    assert_instance_of Buezli::Api::Client::Download, download
    assert_equal "%PDF-example", download.body
    assert_equal "event-12.pdf", download.filename
    assert_equal "application/pdf", download.content_type
    assert_equal "request-123", download.headers["x-request-id"]
    assert_equal "/2026-07-14/events/12/pdf", server.requests.first.path
  ensure
    server&.close
  end

  test "raises structured errors for JSON and non-JSON failures without exposing the token" do
    server = LocalApiServer.new(
      json_response(
        {
          error: {
            message: "An active trial or subscription is required",
            code: "BILLING_REQUIRED",
            details: { account: "inactive" }
          }
        },
        status: 402
      ),
      LocalApiServer::Response.new(
        status: 500,
        headers: { "Content-Type" => "text/plain", "X-Request-Id" => "request-500" },
        body: "Server unavailable"
      )
    )
    client = Buezli::Api::Client.new(access_token: "super-secret", endpoint: server.endpoint, schema: example_schema)

    billing_error = assert_raises(Buezli::Api::Client::Error) { client.retrieve_event(12, expand: [ "organizer" ]) }
    server_error = assert_raises(Buezli::Api::Client::Error) { client.retrieve_event(13) }
    server.finish

    assert_equal 402, billing_error.status
    assert_equal "BILLING_REQUIRED", billing_error.code
    assert_equal "An active trial or subscription is required", billing_error.message
    assert_equal({ "account" => "inactive" }, billing_error.details)
    assert_includes billing_error.response_body, "BILLING_REQUIRED"
    assert_equal "Server unavailable", server_error.message
    assert_equal 500, server_error.status
    assert_nil server_error.code
    assert_equal "request-500", server_error.headers["x-request-id"]
    assert_not_includes billing_error.inspect, "super-secret"

    request = server.requests.first
    assert_equal "/2026-07-14/events/12", request.path
    assert_equal [ "organizer" ], request.query.fetch("expand[]")
  ensure
    server&.close
  end

  test "loads the newest bundled schema and generates every published endpoint" do
    client = Buezli::Api::Client.new(access_token: "secret")

    assert_equal "2026-07-14", client.version
    assert_equal "2026-07-14", client.schema.version
    assert_equal 29, client.singleton_methods.grep(/\Aretrieve_/).size
    assert_respond_to client, :retrieve_account
    assert_respond_to client, :retrieve_memberships
    assert_respond_to client, :retrieve_invoices
    assert_respond_to client, :retrieve_invoice
    assert_respond_to client, :retrieve_invoice_pdf
    assert_respond_to client, :retrieve_estimate_pdf
    assert_respond_to client, :retrieve_expense_receipt
    assert_respond_to client, :retrieve_schema
    assert_not_respond_to client, :retrieve_invoice_line_items
    assert_not_respond_to client, :retrieve_recurring_invoice_line_items
    assert_not client.schema.for("Invoice").key?("description")
    assert_not client.schema.for("Invoice").key?("attribute_descriptions")
  end

  test "reads the account the token belongs to" do
    server = LocalApiServer.new(json_response({
      data: { id: 42, created_at: "2026-07-01T08:00:00Z", updated_at: "2026-07-14T10:00:00Z", name: "Example Studio AG" }
    }))
    client = Buezli::Api::Client.new(access_token: "secret", endpoint: server.endpoint)

    account = client.retrieve_account
    server.finish
    request = server.requests.first

    assert_instance_of Buezli::Api::Client::Record, account
    assert_equal [ 42, "Example Studio AG", Time.utc(2026, 7, 14, 10) ], [ account.id, account.name, account.updated_at ]
    assert_equal "/2026-07-14/account", request.path
    assert_equal "Bearer secret", request.headers.fetch("authorization")
  ensure
    server&.close
  end

  test "uses the published schema for invoice aggregates" do
    client = Buezli::Api::Client.new(access_token: "secret")
    invoice = client.build_record("Invoice", {
      id: 12,
      issue_date: "2026-07-14",
      total: { cents: 10_810, currency: "CHF" },
      line_items: [
        {
          id: 21,
          quantity: "1.25",
          amount: { cents: 10_000, currency: "CHF" }
        }
      ],
      payments: [
        {
          id: 31,
          amount: { cents: 5_000, currency: "CHF" },
          paid_on: "2026-07-15"
        }
      ]
    })

    assert_equal Date.new(2026, 7, 14), invoice.issue_date
    assert_equal({ "cents" => 10_810, "currency" => "CHF" }, invoice.total)
    assert_equal "1.25", invoice.line_items.first.quantity
    assert_equal({ "cents" => 10_000, "currency" => "CHF" }, invoice.line_items.first.amount)
    assert_equal Date.new(2026, 7, 15), invoice.payments.first.paid_on
  end

  test "bundles a valid compact API schema" do
    schema = JSON.parse(BUEZLI_API_ROOT.join("schemas/2026-07-14.json").read)

    assert_equal "2026-07-14", schema.fetch("version")
    assert_equal %w[associations attributes resource_name], schema.dig("models", "Invoice").keys.sort
    assert_equal 29, schema.fetch("endpoints").values.sum(&:size)
    assert_equal "string", schema.dig("models", "TimeEntry", "attributes", "status")
  end

  test "returns a live schema without replacing the client's bundled schema" do
    live_config = example_schema.config.deep_dup
    live_config["models"]["Event"]["attributes"]["new_field"] = "string"
    server = LocalApiServer.new(json_response(live_config))
    client = Buezli::Api::Client.new(access_token: "secret", endpoint: server.endpoint, schema: example_schema)
    configured_schema = client.schema

    live_schema = client.retrieve_schema
    server.finish

    assert_instance_of Buezli::Api::Schema, live_schema
    assert_equal "string", live_schema.attribute_type("Event", "new_field")
    assert_nil client.schema.attribute_type("Event", "new_field")
    assert_same configured_schema, client.schema
  ensure
    server&.close
  end

  test "rejects mismatched versions and invalid path arguments" do
    assert_raises(ArgumentError) do
      Buezli::Api::Client.new(access_token: "secret", version: "2026-07-15", schema: example_schema)
    end

    client = Buezli::Api::Client.new(access_token: "secret", schema: example_schema)

    assert_raises(ArgumentError) { client.retrieve_event }
    assert_raises(ArgumentError) { client.retrieve_event(1, 2) }
  end

  test "does not expose the access token when inspecting the client" do
    client = Buezli::Api::Client.new(access_token: "super-secret", schema: example_schema)

    assert_not_includes client.inspect, "super-secret"
    assert_includes client.inspect, "2026-07-14"
    assert_includes client.inspect, "https://api.buezli.app"
  end

  private

  def example_schema
    Buezli::Api::Schema.new(
      "version" => "2026-07-14",
      "models" => {
        "Event" => {
          "resource_name" => "events",
          "attributes" => {
            "id" => "integer",
            "occurred_on" => "date",
            "amount" => "money",
            "ratio" => "decimal",
            "updated_at" => "datetime"
          },
          "associations" => {
            "organizer" => {
              "type" => "belongs_to",
              "class_name" => "Organizer",
              "inline" => false
            },
            "event_parts" => {
              "type" => "has_many",
              "class_name" => "EventPart",
              "inline" => true
            }
          }
        },
        "EventPart" => {
          "resource_name" => "event_parts",
          "attributes" => {
            "id" => "integer",
            "starts_at" => "datetime"
          },
          "associations" => {}
        },
        "Organizer" => {
          "resource_name" => "organizers",
          "attributes" => { "id" => "integer" },
          "associations" => {}
        }
      },
      "endpoints" => {
        "events" => [
          { "action" => "index", "verb" => "GET", "path" => "/2026-07-14/events" },
          { "action" => "show", "verb" => "GET", "path" => "/2026-07-14/events/:id" },
          { "action" => "pdf", "verb" => "GET", "path" => "/2026-07-14/events/:id/pdf" }
        ],
        "schema" => [
          { "action" => "show", "verb" => "GET", "path" => "/2026-07-14/schema" }
        ]
      }
    )
  end

  def json_response(payload, status: 200)
    LocalApiServer::Response.new(
      status:,
      headers: { "Content-Type" => "application/json" },
      body: JSON.generate(payload)
    )
  end

  class LocalApiServer
    Request = Data.define(:method, :path, :query, :headers, :body)
    Response = Data.define(:status, :headers, :body)

    STATUS_TEXT = {
      200 => "OK",
      400 => "Bad Request",
      401 => "Unauthorized",
      402 => "Payment Required",
      404 => "Not Found",
      500 => "Internal Server Error"
    }.freeze

    attr_reader :port

    def initialize(*responses)
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.local_address.ip_port
      @requests = Queue.new
      @thread = Thread.new { serve(responses) }
    end

    def endpoint
      "http://127.0.0.1:#{port}"
    end

    def requests
      @requests.size.times.map { @requests.pop }
    end

    def finish
      @thread.join
    end

    def close
      @server&.close
      @thread&.kill
      @thread&.join
    rescue IOError
      nil
    end

    private

    def serve(responses)
      responses.each do |response|
        socket = @server.accept
        request_line = socket.gets("\r\n").to_s.strip
        headers = read_headers(socket)
        body = socket.read(headers.fetch("content-length", "0").to_i)
        method, target = request_line.split
        uri = URI(target)
        @requests << Request.new(
          method:,
          path: uri.path,
          query: URI.decode_www_form(uri.query.to_s).to_h { |key, value| [ key, URI.decode_www_form(uri.query.to_s).select { |item| item.first == key }.map(&:last) ] },
          headers:,
          body:
        )
        write_response(socket, response)
      ensure
        socket&.close
      end
    rescue IOError
      nil
    end

    def read_headers(socket)
      headers = {}
      while (line = socket.gets("\r\n"))
        break if line == "\r\n"

        name, value = line.split(":", 2)
        headers[name.downcase] = value.strip
      end
      headers
    end

    def write_response(socket, response)
      headers = response.headers.merge(
        "Content-Length" => response.body.bytesize.to_s,
        "Connection" => "close"
      )
      socket.write("HTTP/1.1 #{response.status} #{STATUS_TEXT.fetch(response.status)}\r\n")
      headers.each { |name, value| socket.write("#{name}: #{value}\r\n") }
      socket.write("\r\n")
      socket.write(response.body)
    end
  end
end
