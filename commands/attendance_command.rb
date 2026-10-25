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
      return professor_reply("아직 학적부에 없는 학생이군. [입학/이름]을 적어. 두 번 말하게 하지 말게.")
    end

    house = user[:house]
    unless house && !house.empty?
      return professor_reply("본인 기숙사도 모르다니... 제정신인가?")
    end

    today = Date.today.to_s

    if user[:attendance_date].to_s.strip == today
      return professor_reply("@#{@sender} 조금 전에 출석한 건 자네가 아니라 머저리였던 모양이군.")
    end

    if Time.now.hour >= 22
      return professor_reply("@#{@sender} 트롤도 이 시간(22:00)엔 자야 한다는 걸 안다네.")
    end

    new_credits = (user[:credits] || 0) + 2
    update_cell(@sender, 'C', new_credits)
    update_cell(@sender, 'L', today)
    add_house_credits(house, 1)

    professor_reply("@#{@sender} #{user[:name]} ...오늘도 지겨운 얼굴이군.\n(보상: 크레딧 +2, #{house} 기숙사 크레딧 +1)")

  rescue => e
    puts "[에러] AttendanceCommand: #{e.message}"
    professor_reply("나중에 다시 오게.")
  end

  private

  def professor_reply(msg)
    @mastodon_client.reply(msg, @status['id'])
  end

  def update_cell(user_id, col, value)
    rows = @sheet_manager.read('사용자', 'A:N')
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
