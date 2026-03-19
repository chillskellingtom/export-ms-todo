# frozen_string_literal: true

# lib/export_ms_todo/graph_client.rb
require 'httparty'
require 'time'

module ExportMsTodo
  class GraphClient
    include HTTParty

    base_uri 'https://graph.microsoft.com/v1.0'

    MAX_RETRIES = 3

    def initialize(token)
      @token = token.start_with?('Bearer ') ? token : "Bearer #{token}"
      @headers = { 'Authorization' => @token }
    end

    def get(path)
      request_with_retry(:get, path)
    end

    def post(path, body: {})
      request_with_retry(:post, path, body: body)
    end

    private

    def request_with_retry(method, path, retries = MAX_RETRIES, body: nil)
      response = if method == :post
                   self.class.post(path, headers: @headers.merge('Content-Type' => 'application/json'),
                                         body: body.to_json)
                 else
                   self.class.get(path, headers: @headers)
                 end

      case response.code
      when 200..299
        response
      when 401
        raise AuthenticationError, 'Invalid or expired token'
      when 429
        retry_after = parse_retry_after(response.headers['Retry-After'])
        raise RateLimitError, "Rate limit exceeded. Retry after #{retry_after} seconds" unless retries.positive?

        warn "Rate limit exceeded. Waiting #{retry_after} seconds..."
        sleep(retry_after)
        request_with_retry(method, path, retries - 1, body: body)

      when 500..599
        raise Error, "Server error: #{response.code}" unless retries.positive?

        sleep(2**(MAX_RETRIES - retries)) # Exponential backoff
        request_with_retry(method, path, retries - 1, body: body)

      else
        raise Error, "Unexpected response: #{response.code}"
      end
    end

    def parse_retry_after(header_val)
      return 60 if header_val.nil? || header_val.empty?

      if header_val.match?(/^\d+$/)
        header_val.to_i
      else
        # Handle HTTP Date format
        (Time.httpdate(header_val) - Time.now).to_i
      end
    rescue StandardError
      60 # Fallback default
    end
  end
end
