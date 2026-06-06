#!/usr/bin/env ruby
# fix_sheet_data.rb
# 사용자 시트의 잘못된 데이터를 정리하고 복구하는 스크립트

require 'bundler/setup'
Bundler.require

require 'date'

puts "=" * 60
puts "사용자 시트 데이터 정리 스크립트"
puts "=" * 60

# Google Sheets 서비스 초기화
begin
  sheets_service = Google::Apis::SheetsV4::SheetsService.new
  credentials = Google::Auth::ServiceAccountCredentials.make_creds(
    json_key_io: File.open('credentials.json'),
    scope: 'https://www.googleapis.com/auth/spreadsheets'
  )
  credentials.fetch_access_token!
  sheets_service.authorization = credentials
  
  puts "✓ Google Sheets 연결 성공"
rescue => e
  puts "✗ Google Sheets 연결 실패: #{e.message}"
  exit 1
end

sheet_id = ENV["GOOGLE_SHEET_ID"]

# 사용자 시트 읽기 (작은따옴표 제거)
range = "사용자!A:M"
begin
  response = sheets_service.get_spreadsheet_values(sheet_id, range)
  data = response.values || []
rescue => e
  puts "✗ 시트 읽기 실패: #{e.message}"
  puts "시트 이름을 확인해주세요."
  exit 1
end

if data.empty?
  puts "✗ 사용자 시트가 비어있습니다."
  exit 1
end

puts "✓ 사용자 시트 읽기 완료 (#{data.length - 1}명)"
puts

# 헤더 확인
headers = data[0]
puts "현재 헤더 구조:"
headers.each_with_index do |header, i|
  col_letter = ('A'.ord + i).chr
  puts "  #{col_letter}: #{header}"
end
puts

# 목표 헤더 구조 (A~K열)
target_headers = [
  "아이디",
  "이름",
  "갈레온",
  "아이템",
  "메모",
  "기숙사",
  "마지막베팅일",
  "오늘베팅횟수",
  "출석날짜",
  "마지막타로일",
  "개별 기숙사 점수"
]

# 인덱스 매핑 (유연하게)
id_idx = headers.index("아이디") || headers.index("사용자 ID") || headers.index("ID") || 0
name_idx = headers.index("이름") || 1
galleon_idx = headers.index("갈레온") || 2
item_idx = headers.index("아이템") || 3
memo_idx = headers.index("메모") || 4
house_idx = headers.index("기숙사") || 5
last_bet_idx = headers.index("마지막베팅일") || headers.index("마지막베팅날짜") || 6
bet_count_idx = headers.index("오늘베팅횟수") || 7
attendance_idx = headers.index("출석날짜") || 8
tarot_idx = headers.index("마지막타로일") || headers.index("마지막타로날짜") || 9
house_score_idx = headers.index("개별 기숙사 점수") || headers.index("기숙사점수") || 10

puts "열 인덱스 매핑:"
puts "  아이디: #{id_idx}"
puts "  이름: #{name_idx}"
puts "  갈레온: #{galleon_idx}"
puts "  기숙사: #{house_idx}"
puts "  출석날짜: #{attendance_idx}"
puts "  개별 기숙사 점수: #{house_score_idx}"
puts

puts "데이터 분석 중..."
puts

# 문제점 분석
issues = {
  invalid_dates: [],
  missing_names: []
}

cleaned_data = [target_headers]

data[1..].each_with_index do |row, idx|
  next if row.nil? || row.empty?
  
  user_id = row[id_idx].to_s.strip
  next if user_id.empty?
  
  name = row[name_idx].to_s.strip
  galleon = row[galleon_idx].to_i
  items = row[item_idx].to_s.strip
  memo = row[memo_idx].to_s.strip
  house = row[house_idx].to_s.strip
  last_bet = row[last_bet_idx].to_s.strip
  bet_count = row[bet_count_idx].to_s.strip
  attendance = row[attendance_idx].to_s.strip
  tarot = row[tarot_idx].to_s.strip
  house_score = row[house_score_idx].to_i
  
  # 1. 잘못된 날짜 수정 (1905-07-18)
  if attendance.include?("1905-07")
    issues[:invalid_dates] << "#{user_id}: 출석날짜"
    attendance = ""
  end
  
  if last_bet.include?("1905-07")
    issues[:invalid_dates] << "#{user_id}: 마지막베팅일"
    last_bet = ""
  end
  
  if tarot.include?("1905-07")
    issues[:invalid_dates] << "#{user_id}: 마지막타로일"
    tarot = ""
  end
  
  # 2. 이름 없음 확인
  if name.empty?
    issues[:missing_names] << user_id
    name = user_id
  end
  
  # 정리된 행 생성 (A~K열만)
  cleaned_row = [
    user_id,
    name,
    galleon,
    items,
    memo,
    house,
    last_bet,
    bet_count,
    attendance,
    tarot,
    house_score
  ]
  
  cleaned_data << cleaned_row
end

# 문제점 리포트
puts "=" * 60
puts "발견된 문제점:"
puts "=" * 60

if issues[:invalid_dates].any?
  puts "\n[잘못된 날짜] #{issues[:invalid_dates].length}건"
  issues[:invalid_dates].each { |issue| puts "  - #{issue}" }
end

if issues[:missing_names].any?
  puts "\n[이름 누락] #{issues[:missing_names].length}건"
  issues[:missing_names].each { |id| puts "  - #{id}" }
end

puts "\n" + "=" * 60
puts "정리된 데이터: #{cleaned_data.length - 1}명"
puts "=" * 60

# 사용자 확인
puts "\n정리된 데이터를 '사용자' 시트에 덮어쓰시겠습니까?"
puts "WARNING: 이 작업은 되돌릴 수 없습니다!"
puts "Google Sheets에서 수동으로 시트를 복사해서 백업하는 것을 권장합니다."
puts
print "계속하려면 'yes'를 입력하세요: "
confirmation = gets.chomp

unless confirmation.downcase == 'yes'
  puts "\n작업이 취소되었습니다."
  exit 0
end

# 기존 데이터 지우기
puts "\n기존 데이터 지우는 중..."
clear_range = "사용자!A1:M1000"
clear_request = Google::Apis::SheetsV4::ClearValuesRequest.new
begin
  sheets_service.clear_values(sheet_id, clear_range, clear_request)
  puts "✓ 기존 데이터 삭제 완료"
rescue => e
  puts "✗ 데이터 삭제 실패: #{e.message}"
  exit 1
end

# 정리된 데이터 쓰기
puts "정리된 데이터 쓰는 중..."
value_range = Google::Apis::SheetsV4::ValueRange.new(values: cleaned_data)
begin
  sheets_service.update_spreadsheet_value(
    sheet_id,
    "사용자!A1",
    value_range,
    value_input_option: 'USER_ENTERED'
  )
  puts "✓ 데이터 쓰기 완료"
rescue => e
  puts "✗ 데이터 쓰기 실패: #{e.message}"
  exit 1
end

puts "\n" + "=" * 60
puts "시트 정리 완료!"
puts "=" * 60
puts "- 총 #{cleaned_data.length - 1}명의 사용자 데이터 정리"
puts "- 잘못된 날짜 #{issues[:invalid_dates].length}건 수정"
puts "- 이름 누락 #{issues[:missing_names].length}건 수정"
puts
puts "다음 단계:"
puts "1. Google Sheets에서 결과 확인"
puts "2. 기숙사 점수 재계산: bundle exec ruby recalculate_house_scores.rb"
puts "3. 교수봇 재시작: pm2 restart professor_bot"
