# main.rb
#!/usr/bin/env ruby
# encoding: UTF-8

require 'mastodon'
require 'dotenv/load'
require 'google/apis/sheets_v4'
require 'googleauth'

require_relative 'mastodon_client'
require_relative 'sheet_manager'
require_relative 'command_parser'

LAST_FILE  = 'last_mention_id.txt'
BASE_URL   = ENV["MASTODON_BASE_URL"]
TOKEN      = ENV["MASTODON_TOKEN"]
SHEET_ID   = ENV["GOOGLE_SHEET_ID"]
CRED_PATH  = ENV["GOOGLE_APPLICATION_CREDENTIALS"]

if BASE_URL.nil? || TOKEN.nil? || SHEET_ID.nil? || CRED_PATH.nil?
  puts "[ERROR] 환경 변수가 빠졌습니다."
  exit 1
end

client = MastodonClient.new(base_url: BASE_URL, token: TOKEN)

Sheets = Google::Apis::SheetsV4
service = Sheets::SheetsService.new
service.client_options.application_name = "FortunaeFons ShopBot"

service.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
  json_key_io: File.open(CRED_PATH),
  scope: ['https://www.googleapis.com/auth/spreadsheets']
)

sheet_manager = SheetManager.new(service, SHEET_ID)

puts "----------------------------------------"
puts "상점봇 시작 - 이전 멘션 무시 모드"
puts "----------------------------------------"

begin
  latest = client.notifications(limit: 1)
  if latest && latest.any?
    last_id = latest.first["id"].to_i
    File.write(LAST_FILE, last_id.to_s)
    puts "최신 멘션 ID로 초기화: #{last_id}"
  else
    last_id = File.exist?(LAST_FILE) ? File.read(LAST_FILE).to_i : 0
    puts "멘션 없음. 기존 ID 사용: #{last_id}"
  end
rescue => e
  puts "[ERROR] 초기화 실패: #{e.message}"
  last_id = File.exist?(LAST_FILE) ? File.read(LAST_FILE).to_i : 0
end

puts "Polling 시작..."
puts "----------------------------------------"

loop do
  begin
    notifications = client.notifications(limit: 40)
    notifications.reverse_each do |n|
      nid = n["id"].to_i
      next unless nid > last_id

      notification_type = n["type"]
      next unless notification_type == "mention"

      acct = n["account"]["acct"]
      puts "[NEW MENTION] ID=#{nid}, from=@#{acct}"

      last_id = nid
      File.write(LAST_FILE, last_id.to_s)

      CommandParser.parse(client, sheet_manager, n)

      sleep 2
    end

  rescue => e
    puts "[ERROR] #{e.class} - #{e.message}"
    puts e.backtrace.first(5).join("\n  ↳ ")
  end

  sleep 7
end
