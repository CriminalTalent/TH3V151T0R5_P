# restore_house_scores_by_date.rb
require 'dotenv/load'
require 'google/apis/sheets_v4'
require 'googleauth'
require 'date'

puts "=========================================="
puts "개별 기숙사 점수 복구 (출석날짜 기반)"
puts "=========================================="

# Google Sheets 서비스 초기화
begin
  sheets_service = Google::Apis::SheetsV4::SheetsService.new
  credentials = Google::Auth::ServiceAccountCredentials.make_creds(
    json_key_io: File.open('credentials.json'),
    scope: 'https://www.googleapis.com/auth/spreadsheets'
  )
  credentials.fetch_access_token!
  sheets_service.authorization = credentials
  spreadsheet = sheets_service.get_spreadsheet(ENV["GOOGLE_SHEET_ID"])
  puts "[성공] Google Sheets 연결: #{spreadsheet.properties.title}"
rescue => e
  puts "[실패] Google Sheets 연결 실패: #{e.message}"
  exit
end

SHEET_ID = ENV["GOOGLE_SHEET_ID"]

# 사용자 시트 읽기 및 출석 횟수 계산
def calculate_scores_from_user_sheet(service, sheet_id)
  range = "사용자!A:K"
  response = service.get_spreadsheet_values(sheet_id, range)
  values = response.values || []
  
  return {} if values.empty?
  
  header = values[0]
  puts "\n[사용자 시트] 헤더: #{header.inspect}"
  
  # 열 인덱스 (0-based)
  # A=0: ID, B=1: 이름, C=2: 갈레온, D=3: 아이템, E=4: 메모, F=5: 기숙사
  # G=6: 마지막베팅일, H=7: 오늘베팅횟수, I=8: 출석날짜, J=9: 마지막타로일, K=10: 개별기숙사점수
  
  attendance_col = 8  # I열 - 출석날짜
  homework_col = 6    # G열 - 과제날짜 (마지막베팅일을 과제날짜로 가정)
  
  scores = {}
  
  values[1..].each_with_index do |row, idx|
    next if row.nil? || row[0].nil?
    
    user_id = row[0].to_s.gsub('@', '').strip
    name = row[1].to_s.strip
    house = row[5].to_s.strip
    current_score = (row[10] || 0).to_i
    
    # 출석날짜가 있으면 1점
    attendance_date = row[attendance_col].to_s.strip
    attendance_score = attendance_date.empty? ? 0 : 1
    
    # 과제날짜 확인 (G열을 과제로 가정)
    homework_date = row[homework_col].to_s.strip
    homework_score = homework_date.empty? ? 0 : 3
    
    total_score = attendance_score + homework_score
    
    scores[user_id] = {
      row_num: idx + 2,
      name: name,
      house: house,
      current_score: current_score,
      calculated_score: total_score,
      attendance: attendance_score > 0,
      homework: homework_score > 0
    }
    
    if total_score > 0
      detail = []
      detail << "출석" if attendance_score > 0
      detail << "과제" if homework_score > 0
      puts "[계산] #{user_id} (#{name}) - #{total_score}점 (#{detail.join(', ')})"
    end
  end
  
  puts "\n[계산 완료] #{scores.size}명 처리"
  scores
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
def print_summary(users_data)
  puts "\n=========================================="
  puts "복구 요약"
  puts "=========================================="
  
  total_users = users_data.size
  users_with_score = users_data.count { |k, v| v[:calculated_score] > 0 }
  
  puts "전체 사용자: #{total_users}명"
  puts "점수 있는 사용자: #{users_with_score}명"
  
  if users_with_score > 0
    puts "\n[점수 있는 사용자 목록]"
    users_data.select { |k, v| v[:calculated_score] > 0 }
              .sort_by { |k, v| -v[:calculated_score] }
              .each do |user_id, data|
      detail = []
      detail << "출석" if data[:attendance]
      detail << "과제" if data[:homework]
      puts "  #{user_id} (#{data[:name]}) [#{data[:house]}] - #{data[:calculated_score]}점 (#{detail.join(', ')})"
    end
  end
  
  # 기숙사별 집계
  house_totals = Hash.new(0)
  users_data.each do |user_id, data|
    next if data[:house].empty?
    house_totals[data[:house]] += data[:calculated_score]
  end
  
  if house_totals.any?
    puts "\n[기숙사별 합계]"
    house_totals.sort_by { |k, v| -v }.each do |house, total|
      member_count = users_data.count { |k, v| v[:house] == house && v[:calculated_score] > 0 }
      puts "  #{house}: #{total}점 (활동 인원: #{member_count}명)"
    end
  end
end

# 메인 실행
begin
  # 사용자 시트에서 직접 계산
  users_data = calculate_scores_from_user_sheet(sheets_service, SHEET_ID)
  
  if users_data.empty?
    puts "\n[오류] 사용자 시트가 비어있습니다."
    exit
  end
  
  # 요약 출력
  print_summary(users_data)
  
  # 확인 후 업데이트
  puts "\n=========================================="
  puts "위 내용으로 점수를 업데이트하시겠습니까?"
  puts "yes 입력 시 실행, 다른 입력 시 취소"
  puts "=========================================="
  print "입력: "
  
  answer = gets.chomp.strip.downcase
  
  if answer == 'yes'
    update_scores(sheets_service, SHEET_ID, users_data)
    puts "\n점수 복구가 완료되었습니다."
  else
    puts "\n[취소] 업데이트가 취소되었습니다."
  end
  
rescue => e
  puts "\n[오류] #{e.message}"
  puts e.backtrace.first(5)
end
