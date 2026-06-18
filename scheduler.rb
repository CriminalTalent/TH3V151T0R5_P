# scheduler.rb
# encoding: UTF-8
# 자동툿 시트(A=ON/OFF체크박스 / B=시간HH:MM / C=내용) 기반으로 스케줄 동적 로딩
# 매 1분마다 현재 시각과 시트 시간을 비교해 툿 발송

require 'rufus-scheduler'
require 'dotenv/load'
require 'google/apis/sheets_v4'
require 'googleauth'

require_relative 'mastodon_client'
require_relative 'sheet_manager'

BASE_URL  = ENV['MASTODON_BASE_URL']
TOKEN     = ENV['MASTODON_TOKEN']
SHEET_ID  = ENV['GOOGLE_SHEET_ID']
CRED_PATH = ENV['GOOGLE_APPLICATION_CREDENTIALS'] || ENV['GOOGLE_CREDENTIALS_PATH']

service = Google::Apis::SheetsV4::SheetsService.new
service.client_options.application_name = 'ProfessorBot'
service.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
  json_key_io: File.open(CRED_PATH),
  scope: ['https://www.googleapis.com/auth/spreadsheets']
)

sheet_manager = SheetManager.new(service, SHEET_ID)
mastodon      = MastodonClient.new(base_url: BASE_URL, token: TOKEN)

puts "[스케줄러] 시작 #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"

sent_today = {}
last_reset_date = Time.now.strftime('%Y-%m-%d')

scheduler = Rufus::Scheduler.new

scheduler.every '1m' do
  now  = Time.now
  date = now.strftime('%Y-%m-%d')
  hhmm       = now.strftime('%H:%M')
  hhmm_short = now.strftime('%-H:%M')

  if date != last_reset_date
    sent_today.clear
    last_reset_date = date
    puts "[스케줄러] 날짜 변경 - 발송 기록 초기화"
  end

  begin
    toots = sheet_manager.load_auto_toots
    toots.each do |toot|
      next unless toot[:time] == hhmm || toot[:time] == hhmm_short
      next if sent_today["#{date}_#{hhmm}_#{toot[:content][0..10]}"]

      mastodon.post_status(toot[:content], visibility: 'public')
      sent_today["#{date}_#{hhmm}_#{toot[:content][0..10]}"] = true
      puts "[자동툿] #{hhmm} 발송: #{toot[:content][0..30]}..."
    end
  rescue => e
    puts "[스케줄러 오류] #{e.message}"
  end
end

puts "[스케줄러] 매 1분마다 자동툿 시트 확인 중..."
scheduler.join
