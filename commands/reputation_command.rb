# commands/reputation_command.rb
# encoding: UTF-8

class ReputationCommand
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

    house_credits = get_house_credits(house)

    professor_reply(
      "@#{@sender}\n" \
      "──────────────────\n" \
      "#{user[:name]}의 기숙사 명성\n" \
      "──────────────────\n" \
      "소속: #{house}\n" \
      "기숙사 총 크레딧: #{house_credits}C\n" \
      "──────────────────"
    )

  rescue => e
    puts "[에러] ReputationCommand: #{e.message}"
    professor_reply("명성 확인 중 오류가 생겼어요. 잠시 후 다시 시도해보세요.")
  end

  private

  def professor_reply(msg)
    @mastodon_client.reply(msg, @status['id'])
  end

  def get_house_credits(house_name)
    rows = @sheet_manager.read('기숙사', 'A:B')
    rows.each_with_index do |row, idx|
      next if idx.zero? || row.nil? || row[0].nil?
      return (row[1] || 0).to_i if row[0].to_s.strip == house_name
    end
    0
  end
end
