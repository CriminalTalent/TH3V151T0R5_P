# commands/homework_command.rb
# 기숙사원 시트 연동 버전 (write 메서드 수정)
require 'date'
require_relative '../utils/professor_control'

class HomeworkCommand
  def initialize(sheet_manager, mastodon_client, sender, status)
    @sheet_manager   = sheet_manager
    @mastodon_client = mastodon_client
    @sender          = sender.gsub('@', '')
    @status          = status
  end

  def execute
    puts "[과제] 실행 시작 - 사용자: #{@sender}"
    
    # 1. 학생 등록 여부 확인
    user = @sheet_manager.find_user(@sender)
    unless user
      puts "[과제] 사용자 없음: #{@sender}"
      return professor_reply("아직 학적부에 이름이 없군요. [입학/이름]으로 먼저 등록해주세요.")
    end

    user_name = user[:name]
    house = user[:house]
    
    unless house && !house.empty?
      puts "[과제] 기숙사 미배정: #{@sender}"
      return professor_reply("아직 기숙사가 배정되지 않았네요. 먼저 기숙사 배정을 받으세요.")
    end

    puts "[과제] 사용자 확인: #{user_name} (#{house})"
    
    today = Date.today.to_s

    # 2. 과제 중복 제출 확인 (G열: 마지막베팅일을 과제날짜로 사용)
    last_homework = user[:last_bet_date].to_s.strip
    puts "[과제] 마지막 과제 제출일: #{last_homework}"
    
    if last_homework == today
      puts "[과제] 오늘 이미 제출함"
      return professor_reply("오늘은 이미 과제를 제출했어요. 하루 한 번만 가능합니다.")
    end

    # 3. 보상 지급
    puts "[과제] 보상 지급 시작..."
    
    # 3-1. 갈레온 지급 (사용자 시트 C열)
    current_galleon = user[:galleons] || 0
    new_galleon = current_galleon + 5
    update_user_cell(@sender, 'C', new_galleon)
    puts "[과제] 갈레온: #{current_galleon} → #{new_galleon}"
    
    # 3-2. 과제 날짜 업데이트 (사용자 시트 G열)
    update_user_cell(@sender, 'G', today)
    puts "[과제] 과제날짜 업데이트: #{today}"
    
    # 3-3. 기숙사원 시트에서 개인점수 +3
    add_house_member_score(@sender, house, 3)
    
    puts "[과제] #{@sender} 과제 제출 완료 - 갈레온 +5, 기숙사 점수 +3"

    # 4. 기숙사 합계 동기화
    sync_house_totals

    # 5. 교수님 피드백
    message = "훌륭해요, #{user_name} 학생.\n과제를 성실히 마쳤군요. 보상으로 5갈레온과 #{house} 점수 +3점을 드립니다."
    professor_reply(message)

  rescue => e
    puts "[에러] HomeworkCommand 처리 중 예외: #{e.message}"
    puts e.backtrace.first(5)
    professor_reply("음... 과제 제출 처리 중 문제가 생긴 것 같아요. 잠시 후 다시 시도해보세요.")
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
