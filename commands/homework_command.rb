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
      return professor_reply("아직 학적부에 이름이 없군. [입학/이름]으로 먼저 등록해.")
    end

    house = user[:house]
    unless house && !house.empty?
      return professor_reply("본인 기숙사도 모르다니... 제정신인가?")
    end

    today = Date.today.to_s

    if user[:homework_date].to_s.strip == today
      return professor_reply("@#{@sender} 그럼 아까 제출한 과제는 태워도 되겠지?")
    end

    new_credits = (user[:credits] || 0) + 5
    update_cell(@sender, 'C', new_credits)
    update_cell(@sender, 'M', today)
    add_house_credits(house, 3)

    professor_reply("@#{@sender} #{user[:name]}.\n이것도 과제라고 한 건가?\n(보상: 크레딧 +5, #{house} 기숙사 크레딧 +3)")

  rescue => e
    puts "[에러] HomeworkCommand: #{e.message}"
    professor_reply("누가 과제를 이따위로 제출하라고 했지? 다시 해 오게.")
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
