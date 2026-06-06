# recalculate_scores_by_period.rb - 특정 기간의 출석/과제 점수 재계산
require 'bundler/setup'
Bundler.require
require 'dotenv'
Dotenv.load('.env')
require 'date'

puts "=========================================="
puts "기간별 개별 기숙사 점수 재계산"
puts "=========================================="

SHEET_ID = ENV["SHEET_ID"] || ENV["GOOGLE_SHEET_ID"]

unless SHEET_ID
  puts "[오류] SHEET_ID 환경변수가 설정되지 않았습니다."
  exit
end

puts "[확인] SHEET_ID: #{SHEET_ID}"

unless File.exist?('credentials.json')
  puts "[오류] credentials.json 파일을 찾을 수 없습니다."
  exit
end

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

# 날짜 파싱 함수
def parse_date(date_str)
  return nil if date_str.nil? || date_str.strip.empty?
  Date.parse(date_str.strip) rescue nil
end

# 날짜가 기간 내에 있는지 확인
def date_in_range?(date_str, start_date, end_date)
  date = parse_date(date_str)
  return false if date.nil?
  date >= start_date && date <= end_date
end

# 특정 기간의 점수 계산 (누적 모드)
def calculate_scores_by_period(service, sheet_id, start_date, end_date, accumulate_mode = false)
  puts "\n[작업] 사용자 시트 읽기 중..."
  puts "[기간] #{start_date} ~ #{end_date}"
  if accumulate_mode
    puts "[모드] 누적 점수 계산 (기존 점수 + 기간 점수)"
  else
    puts "[모드] 기간 점수만 계산 (기존 점수 무시)"
  end
  
  range = "사용자!A:K"
  response = service.get_spreadsheet_values(sheet_id, range)
  values = response.values || []
  
  if values.empty?
    puts "[오류] 사용자 시트가 비어있습니다."
    return {}
  end
  
  header = values[0]
  puts "[확인] 사용자 시트 헤더: #{header.inspect}"
  puts "[확인] 총 #{values.size - 1}명의 사용자 데이터 발견"
  
  # 열 인덱스
  attendance_col = 8  # I열 - 출석날짜
  homework_col = 6    # G열 - 과제날짜 (마지막베팅일)
  
  scores = {}
  attendance_count = 0
  homework_count = 0
  period_total = 0
  
  values[1..].each_with_index do |row, idx|
    next if row.nil? || row[0].nil?
    
    user_id = row[0].to_s.gsub('@', '').strip
    name = row[1].to_s.strip
    house = (row[5] || "").to_s.strip
    current_score = (row[10] || 0).to_i
    
    attendance_date = (row[attendance_col] || "").to_s.strip
    homework_date = (row[homework_col] || "").to_s.strip
    
    # 기간 내 출석 확인
    attendance_score = 0
    attendance_in_period = false
    if date_in_range?(attendance_date, start_date, end_date)
      attendance_score = 1
      attendance_count += 1
      attendance_in_period = true
    end
    
    # 기간 내 과제 확인
    homework_score = 0
    homework_in_period = false
    if date_in_range?(homework_date, start_date, end_date)
      homework_score = 3
      homework_count += 1
      homework_in_period = true
    end
    
    period_score = attendance_score + homework_score
    period_total += period_score
    
    # 누적 모드: 기존 점수 + 기간 점수
    # 기간 모드: 기간 점수만
    final_score = accumulate_mode ? (current_score + period_score) : period_score
    
    scores[user_id] = {
      row_num: idx + 2,
      name: name,
      house: house,
      current_score: current_score,
      period_score: period_score,
      calculated_score: final_score,
      attendance: attendance_in_period,
      homework: homework_in_period,
      attendance_date: attendance_date,
      homework_date: homework_date
    }
    
    if period_score > 0
      detail = []
      detail << "출석(#{attendance_date})" if attendance_in_period
      detail << "과제(#{homework_date})" if homework_in_period
      
      if accumulate_mode
        puts "[계산] #{user_id} (#{name}) - 기존:#{current_score}점 + 기간:#{period_score}점 = 합계:#{final_score}점 (#{detail.join(', ')})"
      else
        puts "[계산] #{user_id} (#{name}) - #{period_score}점 (#{detail.join(', ')})"
      end
    end
  end
  
  puts "\n[계산 완료] #{scores.size}명 처리"
  puts "[통계] 출석: #{attendance_count}회, 과제: #{homework_count}회"
  puts "[기간 총점] #{period_total}점"
  scores
rescue => e
  puts "[오류] #{e.message}"
  puts e.backtrace.first(3)
  {}
end

# 점수 업데이트
def update_scores(service, sheet_id, users_data)
  puts "\n=========================================="
  puts "점수 업데이트 시작"
  puts "=========================================="
  
  update_count = 0
  
  users_data.each do |user_id, data|
    current = data[:current_score]
    new_score = data[:calculated_score]
    
    if current == new_score
      puts "[변경없음] #{user_id} (#{data[:name]}) - #{current}점"
      next
    end
    
    range = "사용자!K#{data[:row_num]}"
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[new_score]])
    
    begin
      service.update_spreadsheet_value(
        sheet_id,
        range,
        value_range,
        value_input_option: 'USER_ENTERED'
      )
      
      puts "[업데이트] #{user_id} (#{data[:name]}) - #{current}점 → #{new_score}점"
      update_count += 1
    rescue => e
      puts "[실패] #{user_id} - #{e.message}"
    end
  end
  
  puts "\n=========================================="
  puts "업데이트 완료: #{update_count}명"
  puts "=========================================="
end

# 요약 출력
def print_summary(users_data, start_date, end_date, accumulate_mode = false)
  puts "\n=========================================="
  if accumulate_mode
    puts "복구 요약 - 누적 모드 (#{start_date} ~ #{end_date})"
  else
    puts "복구 요약 - 기간 모드 (#{start_date} ~ #{end_date})"
  end
  puts "=========================================="
  
  total_users = users_data.size
  users_with_period_score = users_data.count { |k, v| v[:period_score] > 0 }
  total_period_score = users_data.sum { |k, v| v[:period_score] }
  
  puts "전체 사용자: #{total_users}명"
  puts "기간 내 활동 사용자: #{users_with_period_score}명"
  puts "기간 총 획득 점수: #{total_period_score}점"
  
  if accumulate_mode
    total_final_score = users_data.sum { |k, v| v[:calculated_score] }
    puts "전체 누적 점수: #{total_final_score}점"
  end
  
  if users_with_period_score > 0
    puts "\n[기간 내 활동한 사용자 목록]"
    users_data.select { |k, v| v[:period_score] > 0 }
              .sort_by { |k, v| [-v[:calculated_score], -v[:period_score]] }
              .each do |user_id, data|
      detail = []
      detail << "출석(#{data[:attendance_date]})" if data[:attendance]
      detail << "과제(#{data[:homework_date]})" if data[:homework]
      house_info = data[:house].empty? ? "미배정" : data[:house]
      
      if accumulate_mode
        puts "  #{user_id} (#{data[:name]}) [#{house_info}]"
        puts "    기존:#{data[:current_score]}점 + 기간:#{data[:period_score]}점 = 합계:#{data[:calculated_score]}점"
        puts "    #{detail.join(', ')}"
      else
        puts "  #{user_id} (#{data[:name]}) [#{house_info}] - #{data[:calculated_score]}점"
        puts "    #{detail.join(', ')}"
      end
    end
  end
  
  # 기숙사별 집계
  house_period_totals = Hash.new(0)
  house_final_totals = Hash.new(0)
  house_member_counts = Hash.new(0)
  
  users_data.each do |user_id, data|
    next if data[:house].empty? || data[:house] =~ /^\d{4}-\d{2}-\d{2}$/
    house_period_totals[data[:house]] += data[:period_score]
    house_final_totals[data[:house]] += data[:calculated_score]
    house_member_counts[data[:house]] += 1 if data[:period_score] > 0
  end
  
  if house_period_totals.any?
    puts "\n[기숙사별 집계]"
    house_period_totals.keys.sort.each do |house|
      period_total = house_period_totals[house]
      final_total = house_final_totals[house]
      member_count = house_member_counts[house]
      
      if accumulate_mode
        puts "  #{house}:"
        puts "    - 기간 획득: #{period_total}점 (활동: #{member_count}명)"
        puts "    - 전체 누적: #{final_total}점"
      else
        puts "  #{house}: #{period_total}점 (활동: #{member_count}명)"
      end
    end
  end
end

# 메인 실행
begin
  # 기간 입력
  puts "\n=========================================="
  puts "재계산할 기간을 입력하세요"
  puts "=========================================="
  
  print "시작 날짜 (YYYY-MM-DD, 예: 2024-11-15): "
  start_input = gets.chomp.strip
  
  print "종료 날짜 (YYYY-MM-DD, 예: 2024-11-25): "
  end_input = gets.chomp.strip
  
  # 날짜 파싱
  begin
    start_date = Date.parse(start_input)
    end_date = Date.parse(end_input)
  rescue => e
    puts "\n[오류] 날짜 형식이 올바르지 않습니다."
    puts "올바른 형식: YYYY-MM-DD (예: 2024-11-15)"
    exit
  end
  
  if start_date > end_date
    puts "\n[오류] 시작 날짜가 종료 날짜보다 늦습니다."
    exit
  end
  
  # 모드 선택
  puts "\n=========================================="
  puts "점수 계산 모드를 선택하세요"
  puts "=========================================="
  puts "1. 기간 점수만 계산 (해당 기간의 점수만)"
  puts "2. 누적 점수 계산 (기존 점수 + 해당 기간 점수)"
  print "선택 (1 또는 2): "
  
  mode_input = gets.chomp.strip
  accumulate_mode = (mode_input == "2")
  
  # 점수 계산
  users_data = calculate_scores_by_period(sheets_service, SHEET_ID, start_date, end_date, accumulate_mode)
  
  if users_data.empty?
    puts "\n[오류] 처리할 사용자 데이터가 없습니다."
    exit
  end
  
  # 요약 출력
  print_summary(users_data, start_date, end_date, accumulate_mode)
  
  # 확인 후 업데이트
  puts "\n=========================================="
  puts "위 내용으로 점수를 업데이트하시겠습니까?"
  puts "yes 입력 시 실행, 다른 입력 시 취소"
  puts "=========================================="
  print "입력: "
  
  answer = gets.chomp.strip.downcase
  
  if answer == 'yes'
    update_scores(sheets_service, SHEET_ID, users_data)
    puts "\n점수 #{accumulate_mode ? '누적' : '복구'}가 완료되었습니다."
    
    # 기숙사 합계도 업데이트할지 확인
    puts "\n기숙사 합계도 업데이트하시겠습니까? (yes/no)"
    print "입력: "
    
    sync_answer = gets.chomp.strip.downcase
    
    if sync_answer == 'yes'
      puts "\n기숙사 점수를 동기화하려면 다음 명령어를 실행하세요:"
      puts "bundle exec ruby sync_house_scores.rb"
    end
  else
    puts "\n[취소] 업데이트가 취소되었습니다."
  end
  
rescue => e
  puts "\n[오류] #{e.class}: #{e.message}"
  puts e.backtrace.first(3)
end
