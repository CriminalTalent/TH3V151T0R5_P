# scheduler.rb
# encoding: UTF-8
# 자동툿 시트(A=ON/OFF체크박스 / B=시간HH:MM / C=내용 / D=날짜(선택)) 기반으로 스케줄 동적 로딩
# 매 1분마다 현재 시각과 시트 시간을 비교해 툿 발송
# D열(날짜)이 비어있으면 매일 반복, 채워져 있으면 그 날짜에만 발송한다.
# 지원 날짜 형식: YYYY-MM-DD, YYYY/MM/DD, MM-DD, MM/DD, M/D, "M월 D일"(연도는 올해로 간주)

require 'rufus-scheduler'
require 'dotenv/load'
require 'date'
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

# D열(날짜) 문자열을 Date로 파싱. 연도 생략 시 reference_year로 채운다.
# 형식이 안 맞거나 비어있으면 nil을 반환하며, 이 경우 호출부는 "매일 반복"으로 취급한다.
def parse_toot_date(raw, reference_year)
  text = raw.to_s.strip
  return nil if text.empty?

  if text =~ /\A(\d{4})[-\/](\d{1,2})[-\/](\d{1,2})\z/
    y, m, d = $1.to_i, $2.to_i, $3.to_i
  elsif text =~ /\A(\d{1,2})[-\/](\d{1,2})\z/
    y, m, d = reference_year, $1.to_i, $2.to_i
  elsif text =~ /\A(\d{1,2})월\s*(\d{1,2})일?\z/
    y, m, d = reference_year, $1.to_i, $2.to_i
  else
    puts "[스케줄러] 날짜 형식 인식 실패: '#{text}' (매일 반복으로 처리됨)"
    return nil
  end

  Date.new(y, m, d)
rescue
  puts "[스케줄러] 날짜 파싱 오류: '#{raw}'"
  nil
end

scheduler = Rufus::Scheduler.new

scheduler.every '1m' do
  now  = Time.now
  today = Date.today
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

      toot_date = parse_toot_date(toot[:date], today.year)
      next if toot_date && toot_date != today

      key = "#{date}_#{hhmm}_#{toot[:content][0..10]}"
      next if sent_today[key]

      mastodon.post_status(toot[:content], visibility: 'public')
      sent_today[key] = true
      puts "[자동툿] #{hhmm} 발송#{toot_date ? " (#{toot_date})" : ''}: #{toot[:content][0..30]}..."
    end
  rescue => e
    puts "[스케줄러 오류] #{e.message}"
  end
end

puts "[스케줄러] 매 1분마다 자동툿 시트 확인 중..."
scheduler.join
