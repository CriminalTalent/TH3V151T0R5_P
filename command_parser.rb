# command_parser.rb
# encoding: UTF-8
require 'time'
require 'cgi'

require_relative 'commands/buy_command'
require_relative 'commands/sell_command'
require_relative 'commands/transfer_item_command'
require_relative 'commands/transfer_galleons_command'
require_relative 'commands/use_item_command'
require_relative 'commands/pouch_command'
require_relative 'commands/tarot_command'
require_relative 'commands/bet_command'
require_relative 'commands/dice_command'
require_relative 'commands/coin_command'
require_relative 'commands/yn_command'
require_relative 'commands/egg_ingredient_command'

module CommandParser
  @@last_reply_at = {}
  @@cooldown_mutex = Mutex.new

  COOLDOWN_BY_CMD = {
    buy: 10,
    sell: 5,
    transfer_galleons: 10,
    transfer_item: 10,
    use_item: 5,
    pouch: 5,
    tarot: 30,
    bet: 10,
    egg_ingredient: 10,
    dice: 0,
    coin: 0,
    yn: 0
  }.freeze

  TAROT_DATA = {
    "THE FOOL" => "순수한 마음으로 새로운 모험을 시작할 때라네. 망설이지 말고 발을 내딛게, 학생.",
    "THE MAGICIAN" => "지금이 바로 손재주를 발휘할 때라네. 가진 걸 믿고 써먹어보게.",
    "THE HIGH PRIESTESS" => "겉보다 속을 봐야 할 때라네. 조용히 듣고 관찰하게.",
    "THE EMPRESS" => "풍요로움이 넘치는 시기라네. 마음을 열고 주변과 나누게.",
    "THE EMPEROR" => "책임감 있게 자리를 지켜야 할 때라네. 네가 중심을 잡아야 하지.",
    "THE HIEROPHANT" => "배움에는 끝이 없다네. 전통 속에서 해답을 찾아보게.",
    "THE LOVERS" => "선택의 순간이라네. 마음이 진짜 원하는 걸 따라가게.",
    "THE CHARIOT" => "의지와 집중으로 돌파해야 할 때라네. 흔들리지 말게, 학생.",
    "STRENGTH" => "진짜 힘은 온화함에서 나온다네. 조급하지 않게 마음을 다스리게.",
    "THE HERMIT" => "혼자 있는 시간 속에 답이 있다네. 등불을 켜고 내면을 들여다보게.",
    "WHEEL OF FORTUNE" => "운명의 수레바퀴가 돈다네. 이번엔 바람이 어디로 불지 모르지.",
    "JUSTICE" => "공정하게 판단해야 할 때라네. 감정은 잠시 접어두게.",
    "THE HANGED MAN" => "잠시 멈춰보게. 다른 각도에서 보면 세상이 달라진다네.",
    "DEATH" => "끝이 있어야 새 시작이 있지. 두려워 말고 털고 일어나게.",
    "TEMPERANCE" => "균형을 잡아야 한다네. 너무 많지도 적지도 않게 조절하게.",
    "THE DEVIL" => "유혹이 다가오네, 학생. 하지만 스스로 묶이지 말게.",
    "THE TOWER" => "모래성처럼 무너질 수도 있지. 하지만 잔해 위에서 새 출발을 하게.",
    "THE STAR" => "별빛이 아직 남았구먼. 희망을 잃지 말게.",
    "THE MOON" => "착각과 진실이 뒤섞여 있네. 확신은 잠시 미뤄두게.",
    "THE SUN" => "햇살이 쨍하구먼. 지금은 웃어도 좋은 때라네.",
    "JUDGEMENT" => "심판의 나팔이 울린다네. 과거를 정리하고 다시 일어설 차례라네.",
    "THE WORLD" => "모든 것이 제자리에 돌아왔구먼. 완성의 기쁨을 누리게, 학생."
  }.freeze

  def self.cooldown_seconds_for(cmd_key)
    COOLDOWN_BY_CMD[cmd_key] || 10
  end

  def self.cooldown_key(acct, cmd_key)
    "#{acct}::#{cmd_key}"
  end

  def self.cooldown_blocked?(acct, cmd_key)
    cd = cooldown_seconds_for(cmd_key)
    return false if cd.to_i <= 0

    now = Time.now
    key = cooldown_key(acct, cmd_key)

    @@cooldown_mutex.synchronize do
      last = @@last_reply_at[key]
      if last && (now - last) < cd
        diff = (now - last).round(1)
        puts "[REPLY-SKIP] @#{acct} cmd=#{cmd_key} #{diff}s 이내 재요청 → 스킵(쿨타임 #{cd}s)"
        true
      else
        @@last_reply_at[key] = now
        false
      end
    end
  end

  def self.safe_reply(mastodon_client, notification, acct, text, cmd_key: :default, visibility: "unlisted")
    return if text.nil? || text.to_s.strip.empty?

    status_id = notification.is_a?(Hash) ? notification.dig("status", "id") : nil
    unless status_id
      puts "[REPLY-SKIP] @#{acct} status_id를 찾지 못함 → 답글 스킵"
      return
    end

    if cooldown_blocked?(acct, cmd_key)
      return
    end

    begin
      mastodon_client.post_status(text, reply_to_id: status_id, visibility: visibility)
    rescue => e
      puts "[REPLY-ERROR] @#{acct} 답글 중 에러: #{e.class} - #{e.message}"
    end
  end

  def self.parse(mastodon_client, sheet_manager, notification)
    begin
      content_raw  = notification.dig("status", "content") || ""
      account_info = notification["account"] || {}
      sender       = account_info["acct"] || ""
      display      = account_info["display_name"].to_s.strip.empty? ? sender : account_info["display_name"].to_s.strip
      content      = clean_html(content_raw)

      puts "[PARSER] from=@#{sender}(#{display})"
      puts "[PARSER] 정제: #{content}"

      message = nil
      cmd_key = nil

      case content
      when /\[구매\/(.+?)\]/
        item_name = Regexp.last_match(1).to_s.strip
        puts "[PARSER] 구매 명령 감지: #{item_name}"
        cmd_key = :buy
        message = BuyCommand.new(content, sender, sheet_manager).execute
        if message == :player_not_found
          puts "[BUY] ERROR: player not found (@#{sender})"
          return
        end

      when /\[판매\/(.+?)\]/
        item_name = Regexp.last_match(1).to_s.strip
        puts "[PARSER] 판매 명령 감지: #{item_name}"
        cmd_key = :sell
        message = SellCommand.new(sender, item_name, sheet_manager).execute

      when /\[양도\/갈레온\/(\d+)\/@(.+?)\]/i
        amount = Regexp.last_match(1).to_i
        target_acct = Regexp.last_match(2).to_s.strip.split('@').first
        puts "[PARSER] 갈레온 양도: #{amount}G → @#{target_acct}"
        cmd_key = :transfer_galleons
        message = TransferGalleonsCommand.new(sender, target_acct, amount, sheet_manager).execute

      when /\[양도\/(.+?)\/@(.+?)\]/
        item_name   = Regexp.last_match(1).to_s.strip
        target_acct = Regexp.last_match(2).to_s.strip.split('@').first
        puts "[PARSER] 아이템 양도: #{item_name} → @#{target_acct}"
        cmd_key = :transfer_item
        message = TransferItemCommand.new(sender, target_acct, item_name, sheet_manager).execute

      when /\[사용\/(.+?)\]/
        item_name = Regexp.last_match(1).to_s.strip
        puts "[PARSER] 사용 명령 감지: #{item_name}"
        cmd_key = :use_item
        message = UseItemCommand.new(sender, item_name, sheet_manager).execute

      when /\[주머니\]/
        puts "[PARSER] 주머니 명령 감지"
        cmd_key = :pouch
        PouchCommand.new(sender, sheet_manager, mastodon_client, notification).execute
        return

      when /\[타로\]/
        puts "[PARSER] 타로 명령 감지"
        cmd_key = :tarot
        message = TarotCommand.new(sender, TAROT_DATA, sheet_manager).execute

      when /\[베팅\/(\d+)\]/
        amount = Regexp.last_match(1).to_i
        puts "[PARSER] 베팅 명령 감지: #{amount}G"
        cmd_key = :bet
        message = BetCommand.new(sender, amount, sheet_manager).execute

      when /\[계란재료\]/
        puts "[PARSER] 계란재료 명령 감지"
        cmd_key = :egg_ingredient
        message = EggIngredientCommand.new(sender, sheet_manager).execute

      when /\[주사위|d\d+|\d+d\]/i
        puts "[PARSER] 주사위 명령 감지"
        DiceCommand.run(mastodon_client, notification)
        return

      when /\[동전|coin\]/i
        puts "[PARSER] 동전 명령 감지"
        CoinCommand.run(mastodon_client, notification)
        return

      when /\[YN\]/i
        puts "[PARSER] YN 명령 감지"
        YnCommand.run(mastodon_client, notification)
        return

      else
        puts "[PARSER] 명령 없음"
        return
      end

      if message && message != :player_not_found
        puts "[PARSER] 답글 전송 준비(cmd=#{cmd_key}): #{message.to_s[0..50]}..."
        safe_reply(mastodon_client, notification, sender, message, cmd_key: (cmd_key || :default))
      end

    rescue => e
      puts "[에러] 명령어 처리 실패: #{e.message}"
      puts "  ↳ #{e.backtrace.first(5).join("\n  ↳ ")}"
    end
  end

  def self.clean_html(html)
    return "" if html.nil?

    s = html.to_s

    s = s.gsub(/<br\s*\/?>/i, "\n")
         .gsub(/<\/p\s*>/i, "\n")
         .gsub(/<p[^>]*>/i, "")

    s = s.gsub(/<[^>]*>/, "")

    begin
      s = CGI.unescapeHTML(s)
    rescue
    end

    s = s.gsub("\u00A0", " ")
         .gsub(/[ \t]+\n/, "\n")
         .gsub(/\n{3,}/, "\n\n")
         .strip

    s
  end
end
