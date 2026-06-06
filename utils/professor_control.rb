# /root/mastodon_bots/professor_bot/utils/professor_control.rb
require 'date'

module ProfessorControl
  module_function
  # --------------------------------------------------
  # 교수 시트에서 특정 기능(출석, 과제, 자동멘트 등) ON/OFF 상태 확인
  # --------------------------------------------------
  def auto_push_enabled?(sheet_manager, key)
    puts "[ProfessorControl] auto_push_enabled? 체크 - 키: #{key}"
    
    begin
      result = sheet_manager.auto_push_enabled?(key: key)
      puts "[ProfessorControl] #{key} 상태: #{result ? 'ON' : 'OFF'}"
      result
    rescue => e
      puts "[ProfessorControl 에러] auto_push_enabled? 실패: #{e.message}"
      puts e.backtrace.first(3)
      false
    end
  end

  # --------------------------------------------------
  # 특정 시간 범위 내인지 확인 (22시 이후 출석 제한 등)
  # --------------------------------------------------
  def within_time_range?(start_hour, end_hour)
    now = Time.now.hour

    if start_hour < end_hour
      (start_hour <= now && now < end_hour)
    else
      # 예: (22, 6) → 밤 10시~새벽 6시
      (now >= start_hour || now < end_hour)
    end
  end

  # --------------------------------------------------
  # 공지 / 멘트용 포맷 일관화
  # --------------------------------------------------
  def formatted_announcement(type, message)
    timestamp = Time.now.strftime("%H:%M")
    "[#{type}] #{timestamp} - #{message}"
  end
end
