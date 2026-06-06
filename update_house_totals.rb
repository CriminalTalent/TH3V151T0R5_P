#!/usr/bin/env ruby
# update_house_totals.rb - 기숙사원 시트 기반으로 단체 점수 업데이트

require 'bundler/setup'
Bundler.require
require 'dotenv'
Dotenv.load('.env')

SHEET_ID = ENV["SHEET_ID"] || ENV["GOOGLE_SHEET_ID"]

puts "=" * 60
puts "기숙사 단체 점수 업데이트"
puts "=" * 60

# Google Sheets 연결
begin
  sheets_service = Google::Apis::SheetsV4::SheetsService.new
  credentials = Google::Auth::ServiceAccountCredentials.make_creds(
    json_key_io: File.open('credentials.json'),
    scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS
  )
  credentials.fetch_access_token!
  sheets_service.authorization = credentials
  puts "✓ Google Sheets 연결"
rescue => e
  puts "✗ 연결 실패: #{e.message}"
  exit 1
end

# 1단계: 기숙사원 시트에서 점수 집계
puts "\n[1단계] 기숙사원 시트에서 점수 집계..."

house_totals = Hash.new(0)

begin
  response = sheets_service.get_spreadsheet_values(SHEET_ID, "기숙사원!A:D")
  data = response.values || []
  
  if data.empty?
    puts "✗ 기숙사원 시트가 비어있습니다."
    exit 1
  end
  
  data[1..].each do |row|
    next if row.nil? || row[0].nil?
    house = row[0].to_s.strip
    score = (row[3] || 0).to_i
    house_totals[house] += score
  end
  
  puts "✓ 집계 완료:"
  house_totals.sort_by { |k, v| -v }.each do |house, total|
    puts "  #{house}: #{total}점"
  end
  
rescue => e
  puts "✗ 집계 실패: #{e.message}"
  exit 1
end

# 2단계: 모든 시트 이름 확인
puts "\n[2단계] 시트 목록 확인..."

begin
  spreadsheet = sheets_service.get_spreadsheet(SHEET_ID)
  sheet_names = spreadsheet.sheets.map { |s| s.properties.title }
  
  puts "✓ 전체 시트:"
  sheet_names.each_with_index do |name, idx|
    marker = (name =~ /기숙사/i && name != '기숙사원') ? ' ← 이것?' : ''
    puts "  #{idx + 1}. \"#{name}\"#{marker}"
  end
  
rescue => e
  puts "✗ 시트 목록 읽기 실패: #{e.message}"
  exit 1
end

# 3단계: 기숙사 시트 선택
puts "\n[3단계] 기숙사 단체 점수 시트 선택..."

# 자동 감지 시도
house_sheet_candidates = sheet_names.select { |n| n =~ /^기숙사$/i || n =~ /^기숙사\s*$/i }

if house_sheet_candidates.empty?
  puts "⚠️  '기숙사' 시트를 자동으로 찾을 수 없습니다."
  puts "\n단체 점수 시트를 수동으로 선택하세요:"
  sheet_names.each_with_index do |name, idx|
    puts "  #{idx + 1}. #{name}"
  end
  print "\n번호 입력 (1-#{sheet_names.size}): "
  choice = gets.chomp.to_i - 1
  
  if choice < 0 || choice >= sheet_names.size
    puts "✗ 잘못된 선택"
    exit 1
  end
  
  house_sheet_name = sheet_names[choice]
else
  house_sheet_name = house_sheet_candidates.first
end

puts "✓ 선택된 시트: \"#{house_sheet_name}\""

# 4단계: 기숙사 시트 읽기
puts "\n[4단계] 기숙사 시트 읽기..."

begin
  escaped_name = house_sheet_name.gsub("'", "''")
  range = "'#{escaped_name}'!A:B"
  
  response = sheets_service.get_spreadsheet_values(SHEET_ID, range)
  house_data = response.values || []
  
  if house_data.empty?
    puts "✗ 시트가 비어있습니다."
    exit 1
  end
  
  puts "✓ 현재 데이터:"
  house_data.each_with_index do |row, idx|
    if idx == 0
      puts "  헤더: #{row.inspect}"
    else
      puts "  #{row[0]}: #{row[1] || 0}점" if row[0]
    end
  end
  
rescue => e
  puts "✗ 읽기 실패: #{e.message}"
  puts "  시도한 범위: #{range}"
  exit 1
end

# 5단계: 업데이트
puts "\n[5단계] 점수 업데이트..."
print "진행하시겠습니까? (yes/no): "
answer = gets.chomp.strip.downcase

unless answer == 'yes'
  puts "✗ 취소됨"
  exit
end

update_count = 0

house_data[1..].each_with_index do |row, idx|
  next if row.nil? || row[0].nil?
  
  house_name = row[0].to_s.strip
  new_score = house_totals[house_name] || 0
  row_num = idx + 2
  
  begin
    update_range = "'#{escaped_name}'!B#{row_num}"
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[new_score]])
    
    sheets_service.update_spreadsheet_value(
      SHEET_ID,
      update_range,
      value_range,
      value_input_option: 'USER_ENTERED'
    )
    
    puts "  ✓ #{house_name}: #{new_score}점"
    update_count += 1
    
  rescue => e
    puts "  ✗ #{house_name} 업데이트 실패: #{e.message}"
  end
end

puts "\n" + "=" * 60
puts "완료!"
puts "=" * 60
puts "✓ 업데이트: #{update_count}개 기숙사"
puts "\nGoogle Sheets에서 결과를 확인하세요."
