# mastodon_client.rb
# encoding: UTF-8

require 'net/http'
require 'json'
require 'uri'
require 'time'
require 'open-uri'
require 'tempfile'
require 'openssl'
require 'securerandom'

class MastodonClient
  def initialize(base_url:, token:)
    @base_url = base_url.to_s.sub(%r{/\z}, '')
    @token    = token.to_s

    uri = URI(@base_url)
    @http = Net::HTTP.new(uri.host, uri.port)
    @http.use_ssl = (uri.scheme == "https")
    @http.keep_alive_timeout = 30

    @post_block_until = Time.at(0)
  end

  def safe_utf8(str)
    return "" if str.nil?
    s = str.to_s.dup
    s.force_encoding('UTF-8')
    s.valid_encoding? ? s : s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '?')
  rescue
    str.to_s
  end

  def request(method:, path:, params: {}, form: nil, headers: {})
    uri = URI.join(@base_url, path)

    if method == :get && params && params.any?
      uri.query = URI.encode_www_form(params)
    end

    base_headers = { "Authorization" => "Bearer #{@token}" }.merge(headers || {})

    req =
      case method
      when :get
        Net::HTTP::Get.new(uri, base_headers)
      when :post
        r = Net::HTTP::Post.new(uri, base_headers)
        r.set_form_data(form) if form
        r
      else
        raise "Unsupported method: #{method}"
      end

    res = @http.request(req)
    body =
      begin
        JSON.parse(res.body)
      rescue
        {}
      end
    [res, body]
  rescue => e
    puts "[HTTP 오류] #{e.class} - #{e.message}"
    [nil, {}]
  end

  def notifications(limit: 30, since_id: nil, max_id: nil, min_id: nil, types: nil, exclude_types: nil)
    params = {}
    params[:limit]    = limit.to_i if limit
    params[:since_id] = since_id.to_s if since_id
    params[:max_id]   = max_id.to_s if max_id
    params[:min_id]   = min_id.to_s if min_id

    if types && types.respond_to?(:each)
      i = 0
      types.each do |t|
        params["types[#{i}]"] = t.to_s
        i += 1
      end
    end

    if exclude_types && exclude_types.respond_to?(:each)
      i = 0
      exclude_types.each do |t|
        params["exclude_types[#{i}]"] = t.to_s
        i += 1
      end
    end

    res, body = request(method: :get, path: "/api/v1/notifications", params: params)
    return [] unless res && res.code.to_i.between?(200, 299)
    body.is_a?(Array) ? body : []
  end

  def post_status(text, reply_to_id: nil, visibility: "public", media_ids: [])
    return if Time.now < @post_block_until

    form = { status: safe_utf8(text), visibility: visibility }
    form[:in_reply_to_id] = reply_to_id if reply_to_id

    Array(media_ids).each_with_index do |id, i|
      form["media_ids[#{i}]"] = id
    end

    res, _ = request(method: :post, path: "/api/v1/statuses", form: form)

    if res && res.code.to_s == '429'
      reset = res['x-ratelimit-reset']
      @post_block_until =
        begin
          reset ? Time.parse(reset) : (Time.now + 600)
        rescue
          Time.now + 600
        end
      puts "[POST] rate limit → #{@post_block_until} 까지 중단"
    end

    res
  end
end
