# /root/mastodon_bots/professor_bot/professor_command_parser.rb
require_relative 'commands/enroll_command'
require_relative 'commands/attendance_command'
require_relative 'commands/homework_command'

# reply 콜백을 기존 mastodon 객체처럼 사용할 수 있게 감싸는 어댑터
Responder = Struct.new(:cb) do
  # 기존 커맨드들이 mastodon.reply(content, in_reply_to_id) 형태로 호출한다고 가정
  def reply(content, in_reply_to_id)
    cb.call(content, in_reply_to_id)
  end
end

module ProfessorParser
  #   시그니처 변경:
  #   기존: parse(sheet_manager, mastodon, mention)
  #   변경: parse(reply_cb, sheet_manager, mention)
  #
  # main.rb에서는 반드시 ProfessorParser.parse(REPLY, sheet_manager, mention) 로 호출하세요.
  def self.parse(reply_cb, sheet_manager, mention)
    responder = Responder.new(reply_cb)

    # --- mention이 Hash든 OpenStruct든 안전하게 꺼내는 도우미 ---
    status   = digv(mention, 'status')
    account  = digv(mention, 'account')
    content  = extract_content_text(status)        # HTML 태그 제거된 텍스트
    sender_full = extract_acct(account)            # 예: "user@example.com"
    sender  = sender_full.split('@').first
    status_id = digv(status, 'id')

    puts "[교수봇] 처리 중: #{content} (from @#{sender_full})"

    case content
    when /\[입학\/(.+?)\]/  # [입학/이름]
      name = $1.strip
      EnrollCommand.new(sheet_manager, responder, sender, name, status).execute

    when /\[출석\]/
      AttendanceCommand.new(sheet_manager, responder, sender, status).execute

    when /\[과제\]/
      HomeworkCommand.new(sheet_manager, responder, sender, status).execute

    else
      # 인식 불가: 가이드만 회신
      responder.reply("@#{sender_full} 사용 가능한 명령: [입학/이름], [출석], [과제], [주머니]", status_id)
      puts "[무시] 인식되지 않은 명령어: #{content}"
    end
  rescue => e
    puts "[에러] 명령어 파싱 실패: #{e.message}"
    begin
      status_id ||= digv(mention, 'status', 'id')
      sender_full ||= extract_acct(digv(mention, 'account')) rescue 'unknown'
      Responder.new(reply_cb).reply("@#{sender_full} 처리 중 오류가 발생했어요. 잠시 후 다시 시도해 주세요.", status_id) if reply_cb && status_id
    rescue
      # 응답 실패는 조용히 무시
    end
  end

  # --------- 내부 유틸리티 ---------
  def self.digv(obj, *keys)
    cur = obj
    keys.each do |k|
      case cur
      when Hash
        cur = cur[k] || cur[k.to_s] || cur[k.to_sym]
      else
        # OpenStruct 또는 객체 접근 시도
        if cur.respond_to?(k)
          cur = cur.public_send(k)
        elsif cur.respond_to?(k.to_s)
          cur = cur.public_send(k.to_s)
        else
          return nil
        end
      end
    end
    cur
  end

  def self.extract_content_text(status)
    raw = digv(status, 'content') || ''
    raw.to_s.gsub(/<[^>]*>/, '').strip  # HTML 제거
  end

  def self.extract_acct(account)
    digv(account, 'acct') || digv(account, 'username') || 'unknown'
  end
end
