# commands/attendance_command.rb
# encoding: UTF-8
require 'date'

class AttendanceCommand
  def initialize(sheet_manager, mastodon_client, sender, status)
    @sheet_manager   = sheet_manager
    @mastodon_client = mastodon_client
    @sender          = sender.gsub('@', '')
    @status          = status
  end

  def execute
    user = @sheet_manager.find_user(@sender)
    unless user
      return professor_reply("아직 학적부에 없는 학생이군요. [입학/이름]으로 등록을 마쳐주세요.")
    end

    house = user[:house]
    unless house && !house.empty?
      return professor_reply("아직 기숙사가 배정되지 않았네요. 먼저 기숙사 배정을 받으세요.")
    end

    today = Date.today.to_s

    last_attendance = user[:attendance_date].to_s.strip
    if last_attendance == today
      return professor_reply("오늘은 이미 출석을 완료했어요. 성실하군요, 훌륭합니다.")
    end

    if Time.now.hour >= 22
      return professor_reply("출석 마감 시간(22:00)이 지나버렸군요. 내일은 조금 더 일찍 오도록 해요.")
    end

    # 개인 크레딧 +2 (C열)
    new_credits = (user[:credits] || 0) + 2
    update_cell(@sender, 'C', new_credits)

    # 출석날짜 업데이트 (L열)
    update_cell(@sender, 'L', today)

    # 기숙사 크레딧 풀 +1
    add_house_credits(house, 1)

    professor_reply("좋아요, #{user[:name]} 학생. 오늘도 성실히 출석했군요.\n(보상: 크레딧 +2, #{house} 기숙사 크레딧 +1)")

  rescue => e
    puts "[에러] AttendanceCommand: #{e.message}"
    professor_reply("잠시 오류가 생긴 것 같아요. 잠시 후 다시 시도해보세요.")
  end

  private

  def professor_reply(msg)
    @mastodon_client.reply(msg, @status['id'])
  end

  def update_cell(user_id, col, value)
    rows = @sheet_manager.read('사용자', 'A:M')
    rows.each_with_index do |row, idx|
      next if idx.zero? || row.nil? || row[0].nil?
      if row[0].to_s.gsub('@', '').strip == user_id
        @sheet_manager.write('사용자', "#{col}#{idx + 1}", [[value]])
        return true
      end
    end
    false
  end

  def add_house_credits(house_name, amount)
    rows = @sheet_manager.read('기숙사', 'A:B')
    rows.each_with_index do |row, idx|
      next if idx.zero? || row.nil? || row[0].nil?
      if row[0].to_s.strip == house_name
        current = (row[1] || 0).to_i
        @sheet_manager.write('기숙사', "B#{idx + 1}", [[current + amount]])
        return true
      end
    end
    false
  end
end
