# sheet_manager_enhanced.rb
# 기숙사 점수 통합 관리 강화 버전

require 'google/apis/sheets_v4'

class SheetManager
  attr_reader :service, :sheet_id

  USERS_SHEET = '사용자'.freeze
  PROFESSOR_SHEET = '교수'.freeze
  HOUSE_SHEET = '기숙사'.freeze
  HOUSE_MEMBERS_SHEET = '기숙사원'.freeze  # 새로 추가

  def initialize(service, sheet_id)
    @service = service
    @sheet_id = sheet_id
  end

  # =====================================================
  # 🆕 기숙사 점수 통합 관리 메서드
  # =====================================================
  
  # 기숙사원 시트 구조:
  # A: 기숙사 | B: 사용자ID | C: 이름 | D: 개인점수 | E: 최근활동일
  
  def sync_house_system
    puts "[기숙사 동기화] 시작..."
    
    begin
      # 1단계: 사용자 시트에서 기숙사 정보 읽기
      user_data = read_range(a1_range(USERS_SHEET, 'A:K'))
      return if user_data.empty?
      
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
      
      puts "[기숙사 동기화] 집계 완료: #{house_totals.inspect}"
      
      # 2단계: 기숙사원 시트 업데이트 (완전 교체)
      update_house_members_sheet(house_members)
      
      # 3단계: 기숙사 시트 업데이트 (단체 총점만)
      update_house_totals_sheet(house_totals)
      
      puts "[기숙사 동기화] 완료!"
      
      { success: true, house_totals: house_totals }
      
    rescue => e
      puts "[기숙사 동기화 오류] #{e.message}"
      puts e.backtrace.first(5)
      { success: false, error: e.message }
    end
  end
  
  # 기숙사원 시트 업데이트
  def update_house_members_sheet(house_members)
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
    
    # 기존 데이터 지우고 새로 쓰기
    clear_sheet(HOUSE_MEMBERS_SHEET)
    write_range(a1_range(HOUSE_MEMBERS_SHEET, 'A1'), rows)
    
    puts "[기숙사원 시트] #{rows.size - 1}명 업데이트 완료"
  end
  
  # 기숙사 단체 점수 시트 업데이트
  def update_house_totals_sheet(house_totals)
    house_data = read_range(a1_range(HOUSE_SHEET, 'A:B'))
    return if house_data.empty?
    
    house_data[1..].each_with_index do |row, idx|
      next if row.nil? || row[0].nil?
      
      house_name = row[0].to_s.strip
      new_score = house_totals[house_name] || 0
      row_num = idx + 2
      
      range = a1_range(HOUSE_SHEET, "B#{row_num}")
      write_range(range, [[new_score]])
      
      puts "[기숙사 단체 점수] #{house_name}: #{new_score}점"
    end
  end
  
  # 시트 지우기
  def clear_sheet(sheet_name)
    range = a1_range(sheet_name, 'A:Z')
    clear_request = Google::Apis::SheetsV4::ClearValuesRequest.new
    @service.clear_values(@sheet_id, range, clear_request)
  rescue => e
    puts "[시트 지우기 오류] #{e.message}"
  end
  
  # =====================================================
  # 🆕 개인 기숙사 점수 증가 (사용자 시트 K열 업데이트)
  # =====================================================
  def add_house_points(user_id, points, reason = "활동")
    user = find_user(user_id)
    return { success: false, error: "사용자 없음" } unless user
    
    house = user[:house]
    return { success: false, error: "기숙사 미배정" } if house.nil? || house.empty?
    
    # 사용자 시트 K열 업데이트
    new_score = user[:house_score] + points
    success = update_user(user_id, house_score: new_score)
    
    if success
      puts "[개인 점수] #{user_id} → +#{points}점 (#{reason})"
      
      # 즉시 기숙사 동기화
      sync_house_system
      
      {
        success: true,
        user_id: user_id,
        house: house,
        old_score: user[:house_score],
        new_score: new_score,
        points_added: points
      }
    else
      { success: false, error: "업데이트 실패" }
    end
  end
  
  # =====================================================
  # 기존 메서드들 (변경 없음)
  # =====================================================
  
  def read(sheet_name, a1 = 'A:Z')
    ensure_separate_args!(sheet_name, a1)
    read_range(a1_range(sheet_name, a1))
  end

  def write(sheet_name, a1, values)
    ensure_separate_args!(sheet_name, a1)
    write_range(a1_range(sheet_name, a1), values)
  end

  def append(sheet_name, row)
    ensure_separate_args!(sheet_name, 'A:Z')
    append_log(sheet_name, row)
  end

  def a1_range(sheet_name, a1 = 'A:Z')
    sh = sheet_name.to_s
    if sh.include?('!')
      base, rng_from_name = sh.split('!', 2)
      rng = (a1 && a1.strip != '' && a1 != 'A:Z') ? a1 : rng_from_name
      escaped = base.gsub("'", "''")
      "'#{escaped}'!#{rng}"
    else
      escaped = sh.gsub("'", "''")
      "'#{escaped}'!#{a1}"
    end
  end

  def read_range(range)
    response = @service.get_spreadsheet_values(@sheet_id, range)
    response.values || []
  rescue => e
    puts "[시트 읽기 오류] #{e.message}"
    []
  end

  def write_range(range, values)
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: values)
    @service.update_spreadsheet_value(
      @sheet_id,
      range,
      value_range,
      value_input_option: 'USER_ENTERED'
    )
  rescue => e
    puts "[시트 쓰기 오류] #{e.message}"
  end

  def append_log(sheet_name, row)
    range = a1_range(sheet_name, 'A:Z')
    body = Google::Apis::SheetsV4::ValueRange.new(values: [row])

    @service.append_spreadsheet_value(
      @sheet_id,
      range,
      body,
      value_input_option: 'USER_ENTERED'
    )
  rescue => e
    puts "[시트 로그 추가 오류] #{e.message}"
  end

  def find_user(username)
    clean_username = username.to_s.gsub('@', '').strip
    data = read_range(a1_range(USERS_SHEET, 'A:K'))
    return nil if data.empty?

    data.each_with_index do |row, i|
      next if i == 0 || row.nil? || row[0].nil?
      
      row_id = row[0].to_s.gsub('@', '').strip
      
      if row_id == clean_username
        return {
          row_index: i,
          id: row[0].to_s.strip,
          name: row[1].to_s.strip,
          galleons: (row[2] || 0).to_i,
          items: (row[3] || "").to_s.strip,
          memo: (row[4] || "").to_s.strip,
          house: (row[5] || "").to_s.strip,
          last_bet_date: (row[6] || "").to_s.strip,
          today_bet_count: (row[7] || 0).to_i,
          attendance_date: (row[8] || "").to_s.strip,
          last_tarot_date: (row[9] || "").to_s.strip,
          house_score: (row[10] || 0).to_i
        }
      end
    end

    nil
  rescue => e
    puts "[find_user 오류] #{e.message}"
    nil
  end

  def update_user(user_id, data)
    user = find_user(user_id)
    return false unless user
    
    sheet_row = user[:row_index] + 1
    
    row_data = [
      user_id,
      data[:name] || user[:name],
      data[:galleons] || user[:galleons],
      data[:items] || user[:items],
      data[:memo] || user[:memo],
      data[:house] || user[:house],
      data[:last_bet_date] || user[:last_bet_date],
      data[:today_bet_count] || user[:today_bet_count],
      data[:attendance_date] || user[:attendance_date],
      data[:last_tarot_date] || user[:last_tarot_date],
      data[:house_score] || user[:house_score]
    ]
    
    range = a1_range(USERS_SHEET, "A#{sheet_row}:K#{sheet_row}")
    write_range(range, [row_data])
    true
  rescue => e
    puts "[update_user 오류] #{e.message}"
    false
  end

  def increment_user_value(user_id, field, amount)
    user = find_user(user_id)
    return false unless user
    
    case field
    when "갈레온"
      update_user(user_id, galleons: user[:galleons] + amount)
    when "개별 기숙사 점수"
      add_house_points(user_id, amount, "활동")[:success]
    else
      false
    end
  end

  def set_user_value(user_id, field, value)
    user = find_user(user_id)
    return false unless user
    
    case field
    when "출석날짜"
      update_user(user_id, attendance_date: value)
    when "과제날짜"
      update_user(user_id, last_bet_date: value)
    else
      false
    end
  end

  def auto_push_enabled?(key: '아침출석자동툿')
    range = a1_range(PROFESSOR_SHEET, 'A1:Z2')
    data = read_range(range)

    return false if data.empty? || data[0].nil?

    header = data[0]
    values = data[1] || []

    normalized_key = key.to_s.strip.unicode_normalize(:nfkc)
    header_index = header.index { |h| h.to_s.strip.unicode_normalize(:nfkc) == normalized_key }
    return false if header_index.nil?

    val = values[header_index]
    val == true || val.to_s.strip.upcase == 'TRUE' || %w[ON YES 1].include?(val.to_s.strip.upcase)
  rescue => e
    puts "[auto_push_enabled? 오류] #{e.message}"
    false
  end

  private

  def ensure_separate_args!(sheet_name, a1)
    unless sheet_name.is_a?(String) && !sheet_name.strip.empty?
      raise ArgumentError, "시트 이름이 유효하지 않습니다."
    end
    unless a1.is_a?(String) && !a1.strip.empty?
      raise ArgumentError, "A1 범위가 유효하지 않습니다."
    end
  end
end
