# sheet_manager.rb
# encoding: UTF-8
require 'google/apis/sheets_v4'
require 'googleauth'

class SheetManager
  USERS_SHEET     = '사용자'.freeze
  STATS_SHEET     = '스탯'.freeze
  ITEMS_SHEET     = '아이템'.freeze
  HOUSE_SHEET     = '기숙사'.freeze
  PROFESSOR_SHEET = '교수'.freeze
  AUTO_TOOT_SHEET = '자동툿'.freeze

  def initialize(service, sheet_id)
    @service  = service
    @sheet_id = sheet_id
  end

  def read(sheet, range = 'A:Z')
    @service.get_spreadsheet_values(@sheet_id, "#{sheet}!#{range}").values || []
  rescue => e
    puts "[시트 읽기 오류] #{e.message}"
    []
  end

  def write(sheet, range, values)
    body = Google::Apis::SheetsV4::ValueRange.new(values: values)
    @service.update_spreadsheet_value(
      @sheet_id, "#{sheet}!#{range}", body,
      value_input_option: 'USER_ENTERED'
    )
  rescue => e
    puts "[시트 쓰기 오류] #{e.message}"
    false
  end

  def append(sheet, row)
    body = Google::Apis::SheetsV4::ValueRange.new(values: [row])
    @service.append_spreadsheet_value(
      @sheet_id, "#{sheet}!A:Z", body,
      value_input_option: 'USER_ENTERED'
    )
  rescue => e
    puts "[시트 추가 오류] #{e.message}"
    false
  end

  def read_values(range)
    @service.get_spreadsheet_values(@sheet_id, range).values || []
  rescue
    []
  end

  def update_values(range, values)
    body = Google::Apis::SheetsV4::ValueRange.new(values: values)
    @service.update_spreadsheet_value(
      @sheet_id, range, body,
      value_input_option: 'USER_ENTERED'
    )
  rescue => e
    puts "[시트 업데이트 오류] #{e.message}"
    false
  end

  def find_user(acct)
    acct = acct.to_s.gsub('@', '').strip
    rows = read(USERS_SHEET, 'A:M')
    rows[1..].each_with_index do |row, i|
      next unless row[0]&.gsub('@', '')&.strip == acct
      return {
        row_num:         i + 2,
        id:              row[0].to_s.strip,
        name:            row[1].to_s.strip,
        credits:         (row[2] || 0).to_i,
        items:           row[3].to_s,
        house:           row[4].to_s.strip,
        last_bet_date:   row[5].to_s,
        today_bet_count: (row[6] || 0).to_i,
        last_tarot_date: row[7].to_s,
        toot_count:      (row[8] || 0).to_i,
        toot_baseline:   (row[9] || 0).to_i,
        stat_points:     (row[10] || 0).to_i,
        attendance_date: row[11].to_s.strip,
        homework_date:   row[12].to_s.strip
      }
    end
    nil
  rescue => e
    puts "[find_user 오류] #{e.message}"
    nil
  end

  def update_user(acct, attrs)
    acct = acct.to_s.gsub('@', '').strip
    col_map = {
      credits:         'C',
      items:           'D',
      house:           'E',
      last_bet_date:   'F',
      today_bet_count: 'G',
      last_tarot_date: 'H',
      toot_count:      'I',
      toot_baseline:   'J',
      stat_points:     'K',
      attendance_date: 'L',
      homework_date:   'M'
    }
    rows = read(USERS_SHEET, 'A:M')
    rows[1..].each_with_index do |row, i|
      next unless row[0]&.gsub('@', '')&.strip == acct
      row_num = i + 2
      attrs.each do |key, val|
        col = col_map[key]
        next unless col
        write(USERS_SHEET, "#{col}#{row_num}", [[val]])
      end
      return true
    end
    false
  end

  def find_stats(acct)
    acct = acct.to_s.gsub('@', '').strip
    rows = read(STATS_SHEET, 'A:H')
    rows[1..].each_with_index do |row, i|
      next unless row[0]&.gsub('@', '')&.strip == acct
      return {
        row_num:   i + 2,
        id:        row[0].to_s.strip,
        name:      row[1].to_s.strip,
        health:    (row[2] || 50).to_i,
        magic:     (row[3] || 10).to_i,
        endurance: (row[4] || 10).to_i,
        speed:     (row[5] || 0).to_i,
        skill:     (row[6] || 0).to_i,
        luck:      (row[7] || 5).to_i
      }
    end
    nil
  end

  def update_stat(acct, stat_name, new_val)
    acct = acct.to_s.gsub('@', '').strip
    col_map = {
      '건강'    => 'C', '마법능력' => 'D', '인내' => 'E',
      '속도'    => 'F', '기술'     => 'G', '행운' => 'H'
    }
    col = col_map[stat_name]
    return false unless col
    rows = read(STATS_SHEET, 'A:H')
    rows[1..].each_with_index do |row, i|
      next unless row[0]&.gsub('@', '')&.strip == acct
      write(STATS_SHEET, "#{col}#{i + 2}", [[new_val]])
      return true
    end
    false
  end

  def find_item(item_name)
    rows = read(ITEMS_SHEET, 'A:F')
    rows[1..].each do |row|
      next unless row[0]&.strip == item_name.to_s.strip
      return {
        name:        row[0],
        description: row[1],
        price:       row[2].to_i,
        sellable:    row[3].to_s.strip.upcase == 'TRUE' || row[3] == true,
        usable:      row[4].to_s.strip.upcase == 'TRUE' || row[4] == true,
        use_message: row[5].to_s.strip
      }
    end
    nil
  end

  def get_house_credits(house_name)
    rows = read(HOUSE_SHEET, 'A:B')
    rows[1..].each do |row|
      next unless row[0]&.strip == house_name.to_s.strip
      return (row[1] || 0).to_i
    end
    0
  end

  def add_house_credits(house_name, amount)
    rows = read(HOUSE_SHEET, 'A:B')
    rows[1..].each_with_index do |row, i|
      next unless row[0]&.strip == house_name.to_s.strip
      current = (row[1] || 0).to_i
      write(HOUSE_SHEET, "B#{i + 2}", [[current + amount]])
      return true
    end
    false
  end

  def auto_push_enabled?(key:)
    rows = read(PROFESSOR_SHEET, 'A:Z')
    return false if rows.empty?
    header = rows[0] || []
    values = rows[1] || []
    idx = header.index { |h| h.to_s.strip == key.to_s.strip }
    return false unless idx
    val = values[idx]
    val == true || val.to_s.strip.upcase == 'TRUE'
  rescue => e
    puts "[auto_push_enabled? 오류] #{e.message}"
    false
  end

  def load_auto_toots
    rows = read(AUTO_TOOT_SHEET, 'A:C')
    result = []
    rows[1..].each do |row|
      next if row.nil? || row[2].nil? || row[2].to_s.strip.empty?
      enabled = row[0] == true || row[0].to_s.strip.upcase == 'TRUE'
      time    = row[1].to_s.strip
      content = row[2].to_s.strip
      next unless enabled && !time.empty?
      result << { time: time, content: content }
    end
    result
  rescue => e
    puts "[load_auto_toots 오류] #{e.message}"
    []
  end

  def all_users
    rows = read(USERS_SHEET, 'A:M')
    result = []
    rows[1..].each_with_index do |row, i|
      next if row.nil? || row[0].nil?
      result << {
        row_num:         i + 2,
        id:              row[0].to_s.strip,
        name:            row[1].to_s.strip,
        credits:         (row[2] || 0).to_i,
        toot_count:      (row[8] || 0).to_i,
        toot_baseline:   (row[9] || 0).to_i,
        attendance_date: row[11].to_s.strip,
        homework_date:   row[12].to_s.strip,
        house:           row[13].to_s.strip
      }
    end
    result
  end
end
