# recalculate_from_logs.rb - 실제 활동 로그 기반 점수 계산
require 'bundler/setup'
Bundler.require
require 'dotenv'
Dotenv.load('.env')
require 'date'

puts "=========================================="
puts "활동 로그 기반 점수 재계산"
puts "=========================================="

SHEET_ID = ENV["SHEET_ID"] || ENV["GOOGLE_SHEET_ID"]

unless SHEET_ID
  puts "[오류] SHEET_ID 환경변수가 설정되지 않았습니다."
  exit
end

puts "[확인] SHEET_ID: #{SHEET_ID}"

begin
  sheets_service = Google::Apis::SheetsV4::SheetsService.new
  credentials = Google::Auth::ServiceAccountCredentials.make_creds(
    json_key_io: File.open('credentials.json'),
    scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS
  )
  credentials.fetch_access_token!
  sheets_service.authorization = credentials
  spreadsheet = sheets_service.get_spreadsheet(SHEET_ID)
  puts "[성공] Google Sheets 연결: #{spreadsheet.properties.title}"
rescue => e
  puts "[실패] #{e.class}: #{e.message}"
  exit
end

# 날짜 파싱
def parse_date(date_str)
  return nil if date_str.nil? || date_str.strip.empty?
  Date.parse(date_str.strip) rescue nil
end

# 기간 입력
puts "\n=========================================="
puts "집계할 기간을 입력하세요"
puts "=========================================="

print "시작 날짜 (YYYY-MM-DD): "
start_input = gets.chomp.strip

print "종료 날짜 (YYYY-MM-DD): "
end_input = gets.chomp.strip

begin
  start_date = Date.parse(start_input)
  end_date = Date.parse(end_input)
rescue => e
  puts "\n[오류] 날짜 형식이 올바르지 않습니다."
  exit
end

puts "\n[기간] #{start_date} ~ #{end_date}"

# 1. 사용자 목록 로드
puts "\n[1단계] 사용자 목록 로드 중..."
user_range = "사용자!A:K"
user_response = sheets_service.get_spreadsheet_values(SHEET_ID, user_range)
user_values = user_response.values || []

if user_values.empty?
  puts "[오류] 사용자 시트가 비어있습니다."
  exit
end

users = {}
user_values[1..].each_with_index do |row, idx|
  next if row.nil? || row[0].nil?
  user_id = row[0].to_s.gsub('@', '').strip
  users[user_id] = {
    row_num: idx + 2,
    name: row[1].to_s.strip,
    house: (row[5] || "").to_s.strip,
    current_score: (row[10] || 0).to_i,
    attendance_count: 0,
    homework_count: 0,
    attendance_dates: [],
    homework_dates: []
  }
end

puts "[확인] #{users.size}명의 사용자 발견"

# 2. 실제 마스토돈 봇 로그가 있다면 여기서 파싱
# 현재는 시트의 날짜 정보만 사용

puts "\n[2단계] 시트에서 활동 기록 확인 중..."
puts "[알림] 현재 시트에는 마지막 출석/과제 날짜만 기록되어 있습니다."
puts "[알림] 정확한 집계를 위해서는 별도의 활동 로그가 필요합니다."

# 사용자 시트에서 날짜 확인 (최소한의 정보)
user_values[1..].each_with_index do |row, idx|
  next if row.nil? || row[0].nil?
  user_id = row[0].to_s.gsub('@', '').strip
  
  attendance_date_str = (row[8] || "").to_s.strip  # I열
  homework_date_str = (row[6] || "").to_s.strip    # G열
  
  attendance_date = parse_date(attendance_date_str)
  homework_date = parse_date(homework_date_str)
  
  if attendance_date && attendance_date >= start_date && attendance_date <= end_date
    users[user_id][:attendance_count] = 1
    users[user_id][:attendance_dates] << attendance_date_str
  end
  
  if homework_date && homework_date >= start_date && homework_date <= end_date
    users[user_id][:homework_count] = 1
    users[user_id][:homework_dates] << homework_date_str
  end
end

# 3. 점수 계산
puts "\n[3단계] 점수 계산 중..."

total_attendance = 0
total_homework = 0
total_score = 0

users.each do |user_id, data|
  attendance_score = data[:attendance_count] * 1
  homework_score = data[:homework_count] * 3
  calculated_score = attendance_score + homework_score
  
  data[:calculated_score] = calculated_score
  
  total_attendance += data[:attendance_count]
  total_homework += data[:homework_count]
  total_score += calculated_score
  
  if calculated_score > 0
    puts "[계산] #{user_id} (#{data[:name]}): 출석 #{data[:attendance_count]}회(#{attendance_score}점) + 과제 #{data[:homework_count]}회(#{homework_score}점) = #{calculated_score}점"
  end
end

puts "\n[통계]"
puts "  출석 총 #{total_attendance}회"
puts "  과제 총 #{total_homework}회"
puts "  합계 #{total_score}점"

# 4. 요약 출력
puts "\n=========================================="
puts "기간 활동 요약 (#{start_date} ~ #{end_date})"
puts "=========================================="

active_users = users.select { |k, v| v[:calculated_score] > 0 }
puts "활동 사용자: #{active_users.size}명"

if active_users.any?
  puts "\n[사용자별 점수]"
  active_users.sort_by { |k, v| -v[:calculated_score] }.each do |user_id, data|
    house_info = data[:house].empty? ? "미배정" : data[:house]
    puts "  #{user_id} (#{data[:name]}) [#{house_info}] - #{data[:calculated_score]}점"
    
    details = []
    details << "출석 #{data[:attendance_count]}회" if data[:attendance_count] > 0
    details << "과제 #{data[:homework_count]}회" if data[:homework_count] > 0
    puts "    #{details.join(', ')}"
  end
end

# 기숙사별 집계
house_totals = Hash.new(0)
house_counts = Hash.new(0)

users.each do |user_id, data|
  next if data[:house].empty? || data[:house] =~ /^\d{4}-\d{2}-\d{2}$/
  house_totals[data[:house]] += data[:calculated_score]
  house_counts[data[:house]] += 1 if data[:calculated_score] > 0
end

if house_totals.any?
  puts "\n[기숙사별 집계]"
  house_totals.sort_by { |k, v| -v }.each do |house, total|
    count = house_counts[house]
    puts "  #{house}: #{total}점 (활동: #{count}명)"
  end
end

# 5. 경고 메시지
puts "\n=========================================="
puts "중요 안내"
puts "=========================================="
puts "현재 시트에는 '마지막' 출석/과제 날짜만 기록되어 있습니다."
puts "매일 출석했더라도 시트에는 가장 최근 날짜 1개만 있어서"
puts "1회로만 집계됩니다."
puts ""
puts "정확한 점수 집계를 위해서는:"
puts "1. 봇 실행 로그 파일 확인 (professor_bot.log 등)"
puts "2. 마스토돈 타임라인에서 실제 출석/과제 툿 확인"
puts "3. 별도의 활동 로그 시트 생성"
puts ""
puts "이 중 하나가 필요합니다."
puts "=========================================="

# 6. 업데이트 확인
print "\n위 내용으로 점수를 업데이트하시겠습니까? (yes/no): "
answer = gets.chomp.strip.downcase

if answer == 'yes'
  puts "\n[4단계] 점수 업데이트 중..."
  
  update_count = 0
  users.each do |user_id, data|
    next if data[:current_score] == data[:calculated_score]
    
    range = "사용자!K#{data[:row_num]}"
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[data[:calculated_score]]])
    
    begin
      sheets_service.update_spreadsheet_value(
        SHEET_ID,
        range,
        value_range,
        value_input_option: 'USER_ENTERED'
      )
      puts "[업데이트] #{user_id} - #{data[:current_score]}점 → #{data[:calculated_score]}점"
      update_count += 1
    rescue => e
      puts "[실패] #{user_id} - #{e.message}"
    end
  end
  
  puts "\n[완료] #{update_count}명 업데이트됨"
  
  print "\n기숙사 합계도 업데이트하시겠습니까? (yes/no): "
  sync_answer = gets.chomp.strip.downcase
  
  if sync_answer == 'yes'
    puts "\n다음 명령어를 실행하세요:"
    puts "bundle exec ruby sync_house_scores.rb"
  end
else
  puts "\n[취소] 업데이트가 취소되었습니다."
end
