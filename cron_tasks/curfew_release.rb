# ============================================
# cron_tasks/curfew_release.rb
# ============================================
require_relative '../utils/professor_control'
require_relative '../utils/weather_message'

CURFEW_RELEASE_MESSAGES = [
  "좋은 아침이에요. 통금이 풀렸으니 자유롭게 다녀요.",
  "아침이 밝았군요. 이제 어디든 갈 수 있어요.",
  "통금 시간이 끝났어요. 상쾌한 아침 공기 마셔요.",
  "새벽이 지나고 아침이 왔군요. 활기차게 시작해요.",
  "잘 잤나요? 통금 풀렸으니 마음껏 돌아다녀요.",
  "기숙사 문이 열렸어요. 오늘도 좋은 하루 보내요.",
  "통금이 해제되었어요. 아침 산책 어때요?",
  "아침 햇살이 예쁘군요. 통금 풀렸으니 나가봐요.",
  "밤새 푹 잤길 바라요. 이제 자유롭게 다녀요.",
  "통금 시간이 끝났어요. 건강한 하루 보내요.",
  "좋은 아침이에요. 오늘도 즐거운 하루 되세요.",
  "아침이 되니 교수도 기분이 좋군요. 잘 다녀오세요.",
  "통금 풀렸어요. 아침 먹고 수업 가요.",
  "새 아침이에요. 어디든 갈 수 있으니 조심해서 다녀요.",
  "밤이 지나고 낮이 왔군요. 활기차게 보내요.",
  "통금 해제예요. 오늘도 건강하게 지내요.",
  "아침 공기가 맑군요. 깊게 숨 쉬고 다녀요.",
  "잘 잤나요? 통금 끝났으니 자유롭게 활동해요.",
  "기숙사 밖 세상이 기다리고 있어요. 다녀오세요.",
  "통금 시간 끝났어요. 오늘 하루 재미있게 보내요.",
  "아침 해가 밝았군요. 마음껏 돌아다녀요.",
  "새벽이 지나고 아침이에요. 통금 풀렸으니 나가요.",
  "기숙사 복도에 발소리 들려도 괜찮은 시간이에요.",
  "통금이 끝났군요. 조심해서 다녀오세요.",
  "아침이 되니 세상이 밝군요. 자유롭게 다녀요.",
  "통금 해제예요. 오늘도 무사히 보내요.",
  "밤의 규칙이 끝났어요. 마음껏 활동하세요.",
  "창밖에 아침빛이 들어오는군요. 통금 풀렸어요.",
  "밤새 안전하게 지켜줘서 교수도 기쁘네요. 잘 다녀오세요.",
  "아침 해가 떴군요. 통금 끝났으니 즐거운 하루 보내요."
]

def run_curfew_release(sheet_manager, mastodon_client)
  puts "[통금 해제] #{Time.now.strftime('%Y-%m-%d %H:%M:%S')} - 실행 시작"
  
  # 모듈 명시적 호출
  enabled = ProfessorControl.auto_push_enabled?(sheet_manager, "통금해제알람")
  puts "[통금 해제] 기능 상태: #{enabled ? 'ON' : 'OFF'}"
  
  unless enabled
    puts "[스킵] 통금 해제 알람이 OFF 상태입니다."
    return
  end

  # 날씨 메시지 불러오기
  weather_info = WeatherMessage.random_weather_message_with_style
  release_msg = CURFEW_RELEASE_MESSAGES.sample

  # 날씨 + 통금 해제 메시지 조합
  final_message = "#{weather_info[:text]}\n\n#{release_msg}"

  puts "[통금 해제] 전송할 메시지: #{final_message[0..100]}..."
  
  begin
    mastodon_client.broadcast(final_message)
    puts "[통금 해제] 전송 완료"
  rescue => e
    puts "[에러] 통금 해제 알림 전송 실패: #{e.message}"
    puts e.backtrace.first(3)
  end
end
