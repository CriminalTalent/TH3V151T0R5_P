#!/usr/bin/env ruby
# sync_house_unified.rb
# 기숙사 점수 통합 동기화 스크립트

require 'bundler/setup'
Bundler.require

require 'dotenv'
Dotenv.load('.env')

puts "=" * 60
puts "기숙사 통합 동기화 스크립트"
puts "=" * 60

SHEET_ID = ENV["SHEET_ID"] || ENV["GOOGLE_SHEET_ID"]

unless SHEET_ID
  puts "[오류] SHEET_ID 환경변수가 설정되지 않았습니다."
  exit
end

unless File.exist?('credentials.json')
  puts "[오류] credentials.json 파일을 찾을 수 없습니다."
  exit
end

# Google Sheets 연결
begin
  sheets_service = Google::Apis::SheetsV4::SheetsService.new
  credentials = Google::Auth::ServiceAccountCredentials.make_creds(
    json_key_io: File.open('credentials.json'),
    scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS
  )
  credentials.fetch_access_token!
  sheets_service.authorization = credentials
  spreadsheet = sheets_service.get_spreadsheet(SHEET_ID)
  puts "✓ Google Sheets 연결: #{spreadsheet.properties.title}"
rescue => e
  puts "✗ 연결 실패: #{e.message}"
  exit 1
end

# =====================================================
# 1단계: 사용자 시트에서 기숙사 정보 읽기
# =====================================================
puts "\n[1단계] 사용자 시트 읽기..."

begin
  response = sheets_service.get_spreadsheet_values(SHEET_ID, "사용자!A:K")
  user_data = response.values || []
rescue => e
  puts "✗ 읽기 실패: #{e.message}"
  exit 1
end

if user_data.empty?
  puts "✗ 사용자 시트가 비어있습니다."
  exit 1
end

# 기숙사별 사용자 및 점수 집계
house_members = Hash.new { |h, k| h[k] = [] }
house_totals = Hash.new(0)

user_data[1..].each do |row|
  next if row.nil? || row[0].nil?
  
  user_id = row[0].to_s.gsub('@', '').strip
  name = row[1].to_s.strip
  house = (row[5] || "").to_s.strip
  individual_score = (row[10] || 0).to_i
  attendance_date = (row[8] || "").to_s.strip
  
  # 유효한 기숙사만 처리
  next if house.empty? || house =~ /^\d{4}-\d{2}-\d{2}$/
  
  house_members[house] << {
    id: user_id,
    name: name,
    score: individual_score,
    last_activity: attendance_date
  }
  
  house_totals[house] += individual_score
end

puts "✓ 사용자 처리 완료: #{user_data.size - 1}명"
puts "✓ 기숙사별 집계:"
house_totals.sort_by { |k, v| -v }.each do |house, total|
  member_count = house_members[house].size
  puts "  - #{house}: #{total}점 (인원: #{member_count}명)"
end

# =====================================================
# 2단계: 기숙사원 시트 확인 및 생성
# =====================================================
puts "\n[2단계] 기숙사원 시트 확인..."

sheet_list = spreadsheet.sheets.map { |s| s.properties.title }
house_members_sheet_exists = sheet_list.include?('기숙사원')

unless house_members_sheet_exists
  puts "⚠️  '기숙사원' 시트가 없습니다."
  print "새로 생성하시겠습니까? (yes/no): "
  answer = gets.chomp.strip.downcase
  
  if answer == 'yes'
    puts "✓ '기숙사원' 시트를 수동으로 생성해주세요."
    puts "  Google Sheets에서:"
    puts "  1. 새 시트 추가"
    puts "  2. 시트 이름을 '기숙사원'으로 변경"
    puts "  3. 이 스크립트를 다시 실행"
    exit
  else
    puts "✗ 취소되었습니다."
    exit
  end
end

# =====================================================
# 3단계: 기숙사원 시트 업데이트
# =====================================================
puts "\n[3단계] 기숙사원 시트 업데이트..."

rows = [["기숙사", "사용자ID", "이름", "개인점수", "최근활동일"]]

house_members.sort.each do |house, members|
  members.sort_by { |m| -m[:score] }.each do |member|
    rows << [
      house,
      member[:id],
      member[:name],
      member[:score],
      member[:last_activity]
    ]
  end
end

begin
  # 기존 데이터 지우기
  clear_range = "기숙사원!A:Z"
  clear_request = Google::Apis::SheetsV4::ClearValuesRequest.new
  sheets_service.clear_values(SHEET_ID, clear_range, clear_request)
  
  # 새 데이터 쓰기
  value_range = Google::Apis::SheetsV4::ValueRange.new(values: rows)
  sheets_service.update_spreadsheet_value(
    SHEET_ID,
    "기숙사원!A1",
    value_range,
    value_input_option: 'USER_ENTERED'
  )
  
  puts "✓ 기숙사원 시트 업데이트 완료: #{rows.size - 1}명"
rescue => e
  puts "✗ 업데이트 실패: #{e.message}"
  exit 1
end

# =====================================================
# 4단계: 기숙사 단체 점수 업데이트
# =====================================================
puts "\n[4단계] 기숙사 단체 점수 업데이트..."

begin
  response = sheets_service.get_spreadsheet_values(SHEET_ID, "기숙사!A:B")
  house_data = response.values || []
rescue => e
  puts "✗ 기숙사 시트 읽기 실패: #{e.message}"
  exit 1
end

if house_data.empty?
  puts "✗ 기숙사 시트가 비어있습니다."
  exit 1
end

update_count = 0

house_data[1..].each_with_index do |row, idx|
  next if row.nil? || row[0].nil?
  
  house_name = row[0].to_s.strip
  new_score = house_totals[house_name] || 0
  row_num = idx + 2
  
  begin
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[new_score]])
    sheets_service.update_spreadsheet_value(
      SHEET_ID,
      "기숙사!B#{row_num}",
      value_range,
      value_input_option: 'USER_ENTERED'
    )
    
    puts "  ✓ #{house_name}: #{new_score}점"
    update_count += 1
  rescue => e
    puts "  ✗ #{house_name} 업데이트 실패: #{e.message}"
  end
end

puts "✓ 기숙사 단체 점수 업데이트 완료: #{update_count}개"

# =====================================================
# 완료
# =====================================================
puts "\n" + "=" * 60
puts "기숙사 통합 동기화 완료!"
puts "=" * 60
puts "✓ 사용자 처리: #{user_data.size - 1}명"
puts "✓ 기숙사원 시트: #{rows.size - 1}명"
puts "✓ 기숙사 단체 점수: #{update_count}개"
puts "\n다음 단계:"
puts "1. Google Sheets에서 '기숙사원' 시트 확인"
puts "2. 기숙사 시트에서 단체 점수 확인"
puts "3. 교수봇 재시작: pm2 restart professor-bot"
