# /root/mastodon_bots/professor_bot/scheduler.rb
require 'rufus-scheduler'
require 'dotenv/load'

require_relative './mastodon_client'
require_relative './sheet_manager'

require_relative './cron_tasks/morning_attendance_push'
require_relative './cron_tasks/curfew_alert'
require_relative './cron_tasks/curfew_release'

# ----------------------------------------------
# 마스토돈 + 시트 클라이언트 초기화
# ----------------------------------------------
begin
  mastodon = MastodonClient.new(
    base_url: ENV['MASTODON_BASE_URL'],
    token: ENV['MASTODON_TOKEN']
  )
  sheet_manager = SheetManager.new(ENV['GOOGLE_SHEET_ID'])
  puts "[교수봇 스케줄러] 클라이언트 초기화 완료"
rescue => e
  puts "[에러] 클라이언트 초기화 실패: #{e.message}"
  exit 1
end

# ----------------------------------------------
# 스케줄러 시작
# ----------------------------------------------
scheduler = Rufus::Scheduler.new

# ✅ 시트의 ON/OFF 상태 읽기
def get_professor_flags(sheet_manager)
  values = sheet_manager.read('교수!A2:C2')
  return [false, false, false] if values.nil? || values.empty?

  flags = values.first.map do |val|
    val.to_s.strip.casecmp('TRUE').zero? || val == '✅'
  end

  {
    morning: flags[0],   # 아침출석자동툿
    curfew_alert: flags[1],  # 통금알람
    curfew_release: flags[2] # 통금해제알람
  }
rescue => e
  puts "[에러] 시트 상태 읽기 실패: #{e.message}"
  { morning: false, curfew_alert: false, curfew_release: false }
end

# ✅ 공통 안전 래퍼
def safe_task(name)
  yield
rescue => e
  puts "[에러][#{name}] #{e.class}: #{e.message}"
end

# ----------------------------------------------
# 📌 매일 아침 8:00 - 출석 시작 안내 (질문 형식)
# ----------------------------------------------
scheduler.cron '0 8 * * *' do
  flags = get_professor_flags(sheet_manager)
  if flags[:morning]
    safe_task('morning_attendance_push') do
      run_morning_attendance_push(sheet_manager, mastodon)
      puts "[실행됨] 아침출석자동툿"
    end
  else
    puts "[건너뜀] 아침출석자동툿 비활성화됨"
  end
end

# ----------------------------------------------
# 📌 매일 새벽 2:00 - 통금 알림
# ----------------------------------------------
scheduler.cron '0 2 * * *' do
  flags = get_professor_flags(sheet_manager)
  if flags[:curfew_alert]
    safe_task('curfew_alert') do
      run_curfew_alert(sheet_manager, mastodon)
      puts "[실행됨] 통금알람"
    end
  else
    puts "[건너뜀] 통금알람 비활성화됨"
  end
end

# ----------------------------------------------
# 📌 매일 아침 6:00 - 통금 해제 안내
# ----------------------------------------------
scheduler.cron '0 6 * * *' do
  flags = get_professor_flags(sheet_manager)
  if flags[:curfew_release]
    safe_task('curfew_release') do
      run_curfew_release(sheet_manager, mastodon)
      puts "[실행됨] 통금해제알람"
    end
  else
    puts "[건너뜀] 통금해제알람 비활성화됨"
  end
end

puts "[교수봇 스케줄러] 실행 중... Ctrl+C 로 종료 가능"
puts "[스케줄] 8시 출석(질문), 2시 통금, 6시 통금해제"
scheduler.join
