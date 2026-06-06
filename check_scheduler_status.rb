#!/usr/bin/env ruby
# check_scheduler_status.rb
# 교수봇 스케줄러 상태 진단 스크립트

require 'bundler/setup'
require 'dotenv'
Dotenv.load('.env')
require 'google/apis/sheets_v4'
require 'googleauth'
require 'time'

puts "=" * 60
puts "교수봇 스케줄러 상태 진단"
puts "=" * 60
puts "현재 시간: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
puts

# 1. 환경변수 확인
puts "[1단계] 환경변수 확인"
puts "-" * 60

required_envs = {
  'MASTODON_DOMAIN' => ENV['MASTODON_DOMAIN'],
  'ACCESS_TOKEN' => ENV['ACCESS_TOKEN'],
  'SHEET_ID' => ENV['SHEET_ID'],
  'GOOGLE_CREDENTIALS_PATH' => ENV['GOOGLE_CREDENTIALS_PATH']
}

env_ok = true
required_envs.each do |key, value|
  if value.nil? || value.strip.empty?
    puts "[X] #{key}: 설정 안됨"
    env_ok = false
  else
    masked = key.include?('TOKEN') ? "#{value[0..10]}..." : value
    puts "[O] #{key}: #{masked}"
  end
end

unless env_ok
  puts "\n환경변수가 누락되었습니다. .env 파일을 확인하세요."
  exit 1
end

puts

# 2. Google Sheets 연결 확인
puts "[2단계] Google Sheets 연결 확인"
puts "-" * 60

begin
  sheets_service = Google::Apis::SheetsV4::SheetsService.new
  credentials = Google::Auth::ServiceAccountCredentials.make_creds(
    json_key_io: File.open(ENV['GOOGLE_CREDENTIALS_PATH']),
    scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS
  )
  credentials.fetch_access_token!
  sheets_service.authorization = credentials
  
  spreadsheet = sheets_service.get_spreadsheet(ENV['SHEET_ID'])
  puts "[O] Google Sheets 연결 성공"
  puts "    시트 이름: #{spreadsheet.properties.title}"
rescue => e
  puts "[X] Google Sheets 연결 실패: #{e.message}"
  exit 1
end

puts

# 3. 교수 시트 ON/OFF 설정 확인
puts "[3단계] 교수 시트 기능 설정 확인"
puts "-" * 60

begin
  response = sheets_service.get_spreadsheet_values(ENV['SHEET_ID'], "교수!A1:Z2")
  data = response.values
  
  if data.nil? || data.empty?
    puts "[X] 교수 시트가 비어있습니다"
  else
    header = data[0]
    values = data[1] || []
    
    features = [
      '아침출석자동툿',
      '통금알람',
      '통금해제알람'
    ]
    
    features.each do |feature|
      idx = header.index { |h| h.to_s.strip == feature }
      if idx.nil?
        puts "[X] #{feature}: 컬럼을 찾을 수 없음"
      else
        val = values[idx]
        status = (val == true || val.to_s.strip.upcase == 'TRUE' || 
                  %w[ON YES 1].include?(val.to_s.strip.upcase))
        
        if status
          puts "[O] #{feature}: ON"
        else
          puts "[X] #{feature}: OFF (현재값: #{val.inspect})"
        end
      end
    end
  end
rescue => e
  puts "[X] 교수 시트 읽기 실패: #{e.message}"
  puts e.backtrace.first(3)
end

puts

# 4. 서버 시간 및 시간대 확인
puts "[4단계] 서버 시간 및 시간대 확인"
puts "-" * 60

current_time = Time.now
puts "현재 시간: #{current_time.strftime('%Y-%m-%d %H:%M:%S')}"
puts "시간대: #{current_time.zone}"
puts "UTC 오프셋: #{current_time.utc_offset / 3600} 시간"

if current_time.zone == 'KST' || current_time.utc_offset == 32400
  puts "[O] 한국 시간으로 설정됨"
else
  puts "[!] 시간대가 한국(KST)이 아닙니다"
  puts "    .env 파일에 TZ=Asia/Seoul 추가 필요"
end

puts

# 5. 다음 스케줄 실행 시간 계산
puts "[5단계] 다음 스케줄 실행 시간"
puts "-" * 60

schedules = [
  { name: "아침 출석 안내", hour: 8, minute: 0 },
  { name: "통금 알림", hour: 2, minute: 0 },
  { name: "통금 해제 안내", hour: 6, minute: 0 },
  { name: "자정 초기화", hour: 0, minute: 0 }
]

schedules.each do |schedule|
  next_run = Time.new(
    current_time.year,
    current_time.month,
    current_time.day,
    schedule[:hour],
    schedule[:minute],
    0
  )
  
  # 이미 지난 시간이면 내일로
  if next_run <= current_time
    next_run += 24 * 60 * 60
  end
  
  time_until = ((next_run - current_time) / 60).to_i
  hours = time_until / 60
  minutes = time_until % 60
  
  puts "#{schedule[:name]}: #{next_run.strftime('%Y-%m-%d %H:%M')} (#{hours}시간 #{minutes}분 후)"
end

puts

# 6. PM2 프로세스 확인 (시스템 명령어)
puts "[6단계] PM2 프로세스 확인"
puts "-" * 60

pm2_check = `pm2 list 2>&1`
if $?.success?
  if pm2_check.include?('professor')
    puts "[O] professor_bot 프로세스 발견"
    
    # 상태 확인
    if pm2_check.include?('online')
      puts "[O] 상태: online"
    else
      puts "[X] 상태: offline 또는 오류"
    end
  else
    puts "[X] professor_bot 프로세스를 찾을 수 없음"
  end
else
  puts "[!] PM2가 설치되지 않았거나 실행 중이 아님"
end

puts

# 7. 최근 로그 확인
puts "[7단계] 최근 로그 확인"
puts "-" * 60

log_file = "/root/.pm2/logs/professor-bot-out.log"
if File.exist?(log_file)
  recent_logs = `tail -n 20 #{log_file} 2>&1`
  
  if recent_logs.include?('[스케줄러] 시작됨')
    puts "[O] 스케줄러 시작 로그 발견"
  else
    puts "[!] 스케줄러 시작 로그 없음 (재시작 필요할 수 있음)"
  end
  
  if recent_logs.include?('[스케줄러 상태]')
    puts "[O] 스케줄러 정상 작동 로그 발견"
  else
    puts "[!] 스케줄러 작동 확인 로그 없음"
  end
  
  puts "\n최근 로그 (마지막 5줄):"
  puts "-" * 40
  puts recent_logs.lines.last(5).join
else
  puts "[!] 로그 파일을 찾을 수 없음: #{log_file}"
end

puts

# 종합 진단
puts "=" * 60
puts "진단 완료"
puts "=" * 60
puts
puts "다음 단계:"
puts "1. 위에서 [X]로 표시된 항목들을 수정하세요"
puts "2. 교수 시트에서 필요한 기능을 ON으로 설정하세요"
puts "3. 수정 후 봇을 재시작하세요: pm2 restart professor_bot"
puts "4. 로그를 확인하세요: pm2 logs professor_bot --lines 50"
puts
