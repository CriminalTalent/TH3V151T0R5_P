# professor_command_parser.rb
# encoding: UTF-8
require_relative 'commands/enroll_command'
require_relative 'commands/attendance_command'
require_relative 'commands/homework_command'
require_relative 'commands/reputation_command'

Responder = Struct.new(:cb) do
  def reply(content, in_reply_to_id)
    cb.call(content, in_reply_to_id)
  end
end

module ProfessorParser
  def self.parse(reply_cb, sheet_manager, mention)
    responder = Responder.new(reply_cb)

    status      = digv(mention, 'status')
    account     = digv(mention, 'account')
    content     = extract_content_text(status)
    sender_full = extract_acct(account)
    sender      = sender_full.split('@').first
    status_id   = digv(status, 'id')

    puts "[교수봇] #{content} (from @#{sender_full})"

    case content
    when /\[입학\/(.+?)\]/
      EnrollCommand.new(sheet_manager, responder, sender, $1.strip, status).execute

    when /\[출석\]/
      AttendanceCommand.new(sheet_manager, responder, sender, status).execute

    when /\[과제\]/
      HomeworkCommand.new(sheet_manager, responder, sender, status).execute

    when /\[명성확인\]/
      ReputationCommand.new(sheet_manager, responder, sender, status).execute

    else
      responder.reply(
        "@#{sender_full} 사용 가능한 명령: [입학/이름], [출석], [과제], [명성확인]",
        status_id
      )
    end

  rescue => e
    puts "[에러] ProfessorParser: #{e.message}"
    begin
      status_id   ||= digv(mention, 'status', 'id')
      sender_full ||= extract_acct(digv(mention, 'account')) rescue 'unknown'
      Responder.new(reply_cb).reply(
        "@#{sender_full} 처리 중 오류가 발생했어요. 잠시 후 다시 시도해 주세요.",
        status_id
      ) if reply_cb && status_id
    rescue
    end
  end

  def self.digv(obj, *keys)
    cur = obj
    keys.each do |k|
      case cur
      when Hash
        cur = cur[k] || cur[k.to_s] || cur[k.to_sym]
      else
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
    raw.to_s.gsub(/<[^>]*>/, '').strip
  end

  def self.extract_acct(account)
    digv(account, 'acct') || digv(account, 'username') || 'unknown'
  end
end
