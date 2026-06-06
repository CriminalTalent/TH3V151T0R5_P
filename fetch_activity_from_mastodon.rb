# fetch_activity_from_mastodon.rb - 마스토돈에서 실제 활동 내역 가져오기
require 'bundler/setup'
Bundler.require
require 'dotenv'
Dotenv.load('.env')
require 'mastodon'
require 'date'
require 'google/apis/sheets_v4'
require 'googleauth'

puts "=========================================="
puts "마스토돈에서 활동 내역 가져오기"
puts "=========================================="

SHEET_ID = ENV["SHEET_ID"] || ENV["GOOGLE_SHEET_ID"]

# 마스토돈 설정 확인
base_url = ENV['MASTODON_BASE_URL'] || ENV['MASTODON_DOMAIN']
token = ENV['MASTODON_TOKEN'] || ENV['ACCESS_TOKEN']

# base_url에 https:// 추가
unless base_url.to_s.start_with?('http')
  base_url = "https://#{base_url}"
end

puts "[확인] 마스토돈 서버: #{base_url}"
puts "[확인] 토큰 길이: #{token.to_s.length}자"

if token.nil? || token.to_s.strip.empty?
  puts "[오류] 마스토돈 토큰이 설정되지 않았습니다."
  puts "ACCESS_TOKEN 환경변수를 확인하세요."
  exit
end

# 마스토돈 클라이언트 생성
begin
  client = Mastodon::REST::Client.new(
    base_url: base_url,
    bearer_token: token
  )
  puts "[성공] 마스토돈 클라이언트 생성 완료"
rescue => e
  puts "[오류] 마스토돈 클라이언트 생성 실패: #{e.message}"
  exit
end

# 기간 입력
puts "\n=========================================="
print "시작 날짜 (YYYY-MM-DD): "
STDOUT.flush
start_input = gets.chomp.strip

print "종료 날짜 (YYYY-MM-DD): "
STDOUT.flush
end_input = gets.chomp.strip

begin
  start_date = Date.parse(start_input)
  end_date = Date.parse(end_input)
rescue => e
  puts "\n[오류] 날짜 형식이 올바르지 않습니다."
  exit
end

puts "\n[기간] #{start_date} ~ #{end_date}"

# 교수봇 계정 정보
puts "[진행] 교수봇 계정 정보 확인 중..."
begin
  me = client.verify_credentials
  professor_id = me.id
  puts "[확인] 교수봇 계정: @#{me.acct}"
rescue => e
  puts "[오류] 계정 정보 가져오기 실패: #{e.message}"
  puts e.backtrace.first(5)
  exit
end

# 활동 집계
activities = Hash.new { |h, k| h[k] = { attendance: {}, homework: {} } }

puts "\n[진행] 멘션 가져오는 중..."

# 멘션 가져오기
max_id = nil
total_checked = 0
total_found = 0

begin
  5.times do |page|
    options = { limit: 200 }
    options[:max_id] = max_id if max_id
    
    puts "[진행] 페이지 #{page + 1} 로딩 중..."
    notifications = client.notifications(options)
    
    # Mastodon::Collection을 배열로 변환
    notif_array = notifications.to_a
    
    if notif_array.empty?
      puts "[알림] 더 이상 멘션이 없습니다."
      break
    end
    
    notif_array.each do |notif|
      next unless notif.type == 'mention'
      
      status = notif.status
      next unless status
      
      # 날짜 확인
      created_at = Time.parse(status.created_at)
      status_date = created_at.to_date
      
      # 기간 밖이면 스킵
      next if status_date < start_date || status_date > end_date
      
      total_checked += 1
      
      # 멘션 내용 파싱
      content = status.content.gsub(/<[^>]*>/, '').strip
      sender_acct = status.account.acct
      sender_id = sender_acct.split('@').first
      
      date_str = status_date.to_s
      
      # 출석 확인
      if content =~ /\[출석\]/
        activities[sender_id][:attendance][date_str] = true
        total_found += 1
        puts "[발견] #{date_str} - @#{sender_id} 출석"
      end
      
      # 과제 확인
      if content =~ /\[과제\]/
        activities[sender_id][:homework][date_str] = true
        total_found += 1
        puts "[발견] #{date_str} - @#{sender_id} 과제"
      end
    end
    
    # 다음 페이지
    max_id = notif_array.last.id
    
    # 마지막 툿이 기간 시작일보다 이전이면 중단
    last_date = Time.parse(notif_array.last.status.created_at).to_date
    if last_date < start_date
      puts "[알림] 검색 기간을 벗어났습니다."
      break
    end
    
    puts "[진행] #{total_checked}개 확인, #{total_found}개 활동 발견..."
    sleep(0.5)
  end
rescue => e
  puts "[오류] 멘션 가져오기 실패: #{e.message}"
  puts e.backtrace.first(3)
end

puts "\n=========================================="
puts "수집 결과"
puts "=========================================="
puts "확인한 멘션: #{total_checked}개"
puts "발견한 활동: #{total_found}개"

if activities.empty?
  puts "\n[경고] 해당 기간에 활동 내역을 찾을 수 없습니다."
  exit
end

total_attendance = 0
total_homework = 0
total_score = 0

puts "\n[사용자별 활동]"
activities.sort_by { |user_id, data| 
  -(data[:attendance].size + data[:homework].size * 3)
}.each do |user_id, data|
  attendance_count = data[:attendance].keys.size
  homework_count = data[:homework].keys.size
  score = attendance_count * 1 + homework_count * 3
  
  total_attendance += attendance_count
  total_homework += homework_count
  total_score += score
  
  puts "  #{user_id}: 출석 #{attendance_count}회 + 과제 #{homework_count}회 = #{score}점"
  
  if attendance_count > 0
    puts "    출석: #{data[:attendance].keys.sort.join(', ')}"
  end
  if homework_count > 0
    puts "    과제: #{data[:homework].keys.sort.join(', ')}"
  end
end

puts "\n[전체 통계]"
puts "  활동 사용자: #{activities.size}명"
puts "  출석 총합: #{total_attendance}회"
puts "  과제 총합: #{total_homework}회"
puts "  점수 총합: #{total_score}점"

# 기숙사별 집계
puts "\n[진행] 기숙사 정보 로드 중..."

begin
  sheets_service = Google::Apis::SheetsV4::SheetsService.new
  credentials = Google::Auth::ServiceAccountCredentials.make_creds(
    json_key_io: File.open('credentials.json'),
    scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS
  )
  credentials.fetch_access_token!
  sheets_service.authorization = credentials
  
  user_range = "사용자!A:K"
  user_response = sheets_service.get_spreadsheet_values(SHEET_ID, user_range)
  user_values = user_response.values || []
  
  # 사용자 정보 매핑
  user_info = {}
  user_values[1..].each_with_index do |row, idx|
    next if row.nil? || row[0].nil?
    user_id = row[0].to_s.gsub('@', '').strip
    user_info[user_id] = {
      row_num: idx + 2,
      name: row[1].to_s.strip,
      house: (row[5] || "").to_s.strip
    }
  end
  
  # 기숙사별 집계
  house_totals = Hash.new(0)
  house_counts = Hash.new(0)
  
  activities.each do |user_id, data|
    next unless user_info[user_id]
    house = user_info[user_id][:house]
    next if house.empty? || house =~ /^\d{4}-\d{2}-\d{2}$/
    
    attendance_count = data[:attendance].keys.size
    homework_count = data[:homework].keys.size
    score = attendance_count * 1 + homework_count * 3
    
    house_totals[house] += score
    house_counts[house] += 1
  end
  
  if house_totals.any?
    puts "\n[기숙사별 집계]"
    house_totals.sort_by { |k, v| -v }.each do |house, total|
      count = house_counts[house]
      puts "  #{house}: #{total}점 (활동: #{count}명)"
    end
  end
  
  # 시트 업데이트
  puts "\n=========================================="
  print "이 내용을 시트에 반영하시겠습니까? (yes/no): "
  STDOUT.flush
  answer = gets.chomp.strip.downcase
  
  if answer == 'yes'
    puts "\n[진행] 시트 업데이트 중..."
    update_count = 0
    
    activities.each do |user_id, data|
      next unless user_info[user_id]
      
      attendance_count = data[:attendance].keys.size
      homework_count = data[:homework].keys.size
      new_score = attendance_count * 1 + homework_count * 3
      
      row_num = user_info[user_id][:row_num]
      range = "사용자!K#{row_num}"
      value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[new_score]])
      
      sheets_service.update_spreadsheet_value(
        SHEET_ID,
        range,
        value_range,
        value_input_option: 'USER_ENTERED'
      )
      
      name = user_info[user_id][:name]
      puts "[업데이트] #{user_id} (#{name}) - #{new_score}점"
      update_count += 1
    end
    
    puts "\n[완료] #{update_count}명 업데이트됨"
    
    print "\n기숙사 합계도 업데이트하시겠습니까? (yes/no): "
    STDOUT.flush
    sync_answer = gets.chomp.strip.downcase
    
    if sync_answer == 'yes'
      puts "\n[진행] 기숙사 점수 동기화 중..."
      
      # 기숙사 시트 읽기
      house_range = "기숙사!A:B"
      house_response = sheets_service.get_spreadsheet_values(SHEET_ID, house_range)
      house_values = house_response.values || []
      
      # 사용자 시트에서 모든 사용자의 개별 기숙사 점수 합산
      recalc_house_totals = Hash.new(0)
      user_values[1..].each do |row|
        next if row.nil? || row[0].nil?
        house = (row[5] || "").to_s.strip
        next if house.empty? || house =~ /^\d{4}-\d{2}-\d{2}$/
        individual_score = (row[10] || 0).to_i
        recalc_house_totals[house] += individual_score
      end
      
      # 기숙사 시트 업데이트
      house_values[1..].each_with_index do |row, idx|
        next if row.nil? || row[0].nil?
        house_name = row[0].to_s.strip
        if recalc_house_totals.key?(house_name)
          row_num = idx + 2
          new_total = recalc_house_totals[house_name]
          range = "기숙사!B#{row_num}"
          value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[new_total]])
          
          sheets_service.update_spreadsheet_value(
            SHEET_ID,
            range,
            value_range,
            value_input_option: 'USER_ENTERED'
          )
          
          puts "[동기화] #{house_name}: #{new_total}점"
        end
      end
      
      puts "\n[완료] 기숙사 점수 동기화 완료"
    end
  else
    puts "[취소] 시트 업데이트가 취소되었습니다."
  end
  
rescue => e
  puts "[오류] #{e.message}"
  puts e.backtrace.first(3)
end
