# commands/attendance_command.rb
# 기숙사원 시트 연동 버전 (write 메서드 수정)
require_relative '../utils/professor_control'
require 'date'

class AttendanceCommand
  def initialize(sheet_manager, mastodon_client, sender, status)
    @sheet_manager = sheet_manager
    @mastodon_client = mastodon_client
    @sender = sender.gsub('@', '')
    @status = status
  end

  def execute
    puts "[출석] 실행 시작 - 사용자: #{@sender}"
    
    # 1. 학생 정보 확인
    user = @sheet_manager.find_user(@sender)
    unless user
      puts "[출석] 사용자 없음: #{@sender}"
      return professor_reply("아직 학적부에 없는 학생이군요. [입학/이름]으로 등록을 마쳐주세요.")
    end

    user_name = user[:name]
    house = user[:house]
    
    unless house && !house.empty?
      puts "[출석] 기숙사 미배정: #{@sender}"
      return professor_reply("아직 기숙사가 배정되지 않았네요. 먼저 기숙사 배정을 받으세요.")
    end

    puts "[출석] 사용자 확인: #{user_name} (#{house})"

    # 2. 출석 기능 상태 확인
    unless ProfessorControl.auto_push_enabled?(@sheet_manager, "아침출석자동툿")
      puts "[출석] 출석 기능 비활성화됨"
      return professor_reply("지금은 출석 기능이 잠시 중단된 상태예요. 나중에 다시 시도해보세요.")
    end

    today = Date.today.to_s
    current_time = Time.now

    # 3. 중복 출석 방지
    last_attendance = user[:attendance_date].to_s.strip
    puts "[출석] 마지막 출석일: #{last_attendance}"
    
    if last_attendance == today
      puts "[출석] 오늘 이미 출석함"
      return professor_reply("오늘은 이미 출석을 완료했어요. 성실하군요, 훌륭합니다.")
    end

    # 4. 출석 가능 시간 확인 (22시 이전)
    if current_time.hour >= 22
      puts "[출석] 출석 마감 시간 지남"
      return professor_reply("출석 마감 시간(22:00)이 지나버렸군요. 내일은 조금 더 일찍 오도록 해요.")
    end

    # 5. 출석 처리
    puts "[출석] 보상 지급 시작..."
    
    # 5-1. 갈레온 지급 (사용자 시트 C열)
    current_galleon = user[:galleons] || 0
    new_galleon = current_galleon + 2
    update_user_cell(@sender, 'C', new_galleon)
    puts "[출석] 갈레온: #{current_galleon} → #{new_galleon}"
    
    # 5-2. 출석 날짜 업데이트 (사용자 시트 I열)
    update_user_cell(@sender, 'I', today)
    puts "[출석] 출석날짜 업데이트: #{today}"
    
    # 5-3. 기숙사원 시트에서 개인점수 +1
    add_house_member_score(@sender, house, 1)
    
    puts "[출석] #{@sender} 출석 완료 - 갈레온 +2, 기숙사 점수 +1"

    # 6. 기숙사 합계 동기화
    sync_house_totals

    # 7. 교수님식 출석 멘트
    message = "좋아요, #{user_name} 학생. 오늘도 성실히 출석했군요.\n(보상: 2갈레온, #{house} 점수 +1)"
    professor_reply(message)

  rescue => e
    puts "[에러] AttendanceCommand 처리 중 예외: #{e.message}"
    puts e.backtrace.first(5)
    professor_reply("음… 잠시 오류가 생긴 것 같아요. 잠시 후 다시 시도해보세요.")
  end

  private

  def professor_reply(message)
    @mastodon_client.reply(message, @status['id'])
  end

  # 사용자 시트 특정 셀 업데이트 (수정된 버전)
  def update_user_cell(user_id, column, value)
    data = @sheet_manager.read('사용자', 'A:J')
    return false if data.empty?

    data.each_with_index do |row, idx|
      next if idx.zero? || row.nil? || row[0].nil?
      
      if row[0].to_s.gsub('@', '').strip == user_id
        row_num = idx + 1
        range = "#{column}#{row_num}"
        # ✅ 올바른 호출: write(시트명, 범위, 값)
        @sheet_manager.write('사용자', range, [[value]])
        puts "[업데이트] 사용자!#{range} = #{value}"
        return true
      end
    end
    
    false
  rescue => e
    puts "[에러] update_user_cell 실패: #{e.message}"
    false
  end

  # 기숙사원 시트에서 개인점수 증가 (수정된 버전)
  def add_house_member_score(user_id, house, points)
    data = @sheet_manager.read('기숙사원', 'A:E')
    
    if data.empty?
      puts "[경고] 기숙사원 시트가 비어있음"
      return false
    end

    # 기존 회원 찾기
    found = false
    data.each_with_index do |row, idx|
      next if idx.zero? || row.nil? || row[1].nil?
      
      if row[1].to_s.strip == user_id
        found = true
        current_score = (row[3] || 0).to_i
        new_score = current_score + points
        row_num = idx + 1
        
        # D열(개인점수) 업데이트
        @sheet_manager.write('기숙사원', "D#{row_num}", [[new_score]])
        
        # E열(최근활동일) 업데이트
        @sheet_manager.write('기숙사원', "E#{row_num}", [[Date.today.to_s]])
        
        puts "[기숙사원] #{user_id} 점수: #{current_score} → #{new_score}"
        return true
      end
    end

    # 기존 회원이 없으면 새로 추가
    unless found
      user = @sheet_manager.find_user(user_id)
      new_row = [
        house,
        user_id,
        user[:name],
        points,
        Date.today.to_s
      ]
      @sheet_manager.append('기숙사원', new_row)
      puts "[기숙사원] 신규 추가: #{user_id} (#{points}점)"
    end

    true
  rescue => e
    puts "[에러] add_house_member_score 실패: #{e.message}"
    puts e.backtrace.first(3)
    false
  end

  # 기숙사 시트 합계 동기화 (수정된 버전)
  def sync_house_totals
    # 1. 기숙사원 시트에서 기숙사별 합계 계산
    member_data = @sheet_manager.read('기숙사원', 'A:D')
    return if member_data.empty?

    house_totals = Hash.new(0)
    
    member_data[1..].each do |row|
      next if row.nil? || row[0].nil?
      house_name = row[0].to_s.strip
      score = (row[3] || 0).to_i
      house_totals[house_name] += score
    end

    puts "[동기화] 기숙사별 합계: #{house_totals.inspect}"

    # 2. 기숙사 시트 업데이트
    house_data = @sheet_manager.read('기숙사', 'A:B')
    return if house_data.empty?

    house_data.each_with_index do |row, idx|
      next if idx.zero? || row.nil? || row[0].nil?
      
      house_name = row[0].to_s.strip
      new_total = house_totals[house_name] || 0
      row_num = idx + 1
      
      # ✅ 올바른 호출
      @sheet_manager.write('기숙사', "B#{row_num}", [[new_total]])
      puts "[동기화] #{house_name}: #{new_total}점"
    end

  rescue => e
    puts "[에러] sync_house_totals 실패: #{e.message}"
    puts e.backtrace.first(3)
  end
end
