# commands/homework_command.rb
# encoding: UTF-8
require 'date'

class HomeworkCommand
  def initialize(sheet_manager, mastodon_client, sender, status)
    @sheet_manager   = sheet_manager
    @mastodon_client = mastodon_client
    @sender          = sender.gsub('@', '')
    @status          = status
  end

  def execute
    user = @sheet_manager.find_user(@sender)
    unless user
      return professor_reply("아직 학적부에 이름이 없군요. [입학/이름]으로 먼저 등록해주세요.")
    end

    house = user[:house]
    unless house && !house.empty?
      return professor_reply("아직 기숙사가 배정되지 않았네요. 먼저 기숙사 배정을 받으세요.")
    end

    today = Date.today.to_s

    last_homework = user[:homework_date].to_s.strip
    if last_homework == today
      return professor_reply("오늘은 이미 과제를 제출했어요. 하루 한 번만 가능합니다.")
    end

    # 개인 크레딧 +5 (C열)
    new_credits = (user[:credits] || 0) + 5
    update_cell(@sender, 'C', new_credits)

    # 과제날짜 업데이트 (M열)
    update_cell(@sender, 'M', today)

    # 기숙사 크레딧 풀 +3
    add_house_credits(house, 3)

    professor_reply("훌륭해요, #{user[:name]} 학생.\n과제를 성실히 마쳤군요.\n(보상: 크레딧 +5, #{house} 기숙사 크레딧 +3)")

  rescue => e
    puts "[에러] HomeworkCommand: #{e.message}"
    professor_reply("과제 제출 처리 중 문제가 생긴 것 같아요. 잠시 후 다시 시도해보세요.")
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
