#!/usr/bin/env ruby
# check_sheets.rb - 스프레드시트의 모든 시트 이름 확인

require 'bundler/setup'
Bundler.require

puts "스프레드시트 정보 확인 중..."

sheets_service = Google::Apis::SheetsV4::SheetsService.new
credentials = Google::Auth::ServiceAccountCredentials.make_creds(
  json_key_io: File.open('credentials.json'),
  scope: 'https://www.googleapis.com/auth/spreadsheets'
)
credentials.fetch_access_token!
sheets_service.authorization = credentials

sheet_id = ENV["GOOGLE_SHEET_ID"]

# 스프레드시트 메타데이터 가져오기
spreadsheet = sheets_service.get_spreadsheet(sheet_id)

puts "\n스프레드시트: #{spreadsheet.properties.title}"
puts "\n시트 목록:"
puts "=" * 60

spreadsheet.sheets.each_with_index do |sheet, idx|
  sheet_title = sheet.properties.title
  sheet_id = sheet.properties.sheet_id
  puts "#{idx + 1}. \"#{sheet_title}\" (ID: #{sheet_id})"
end

puts "\n사용할 시트 이름을 정확히 복사해서 스크립트에 사용하세요."
