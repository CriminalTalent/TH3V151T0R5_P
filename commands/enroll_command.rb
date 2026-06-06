# commands/enroll_command.rb
require 'date'

class EnrollCommand
  INITIAL_GALLEON = 20

  def initialize(sheet_manager, mastodon_client, sender, name, status)
    @sheet_manager = sheet_manager
    @mastodon_client = mastodon_client
    @sender = sender.gsub('@', '')
    @name = name
    @status = status
  end

  def execute
    existing_user = @sheet_manager.find_user(@sender)

    if existing_user
      @mastodon_client.reply(@status, "#{@name} 학생은 이미 입학한 상태입니다.")
      return
    end

    # 1단계: 사용자 시트 등록 (A~K열 구조)
    user_row = [
      @sender,         # A: 사용자 ID
      @name,           # B: 이름
      INITIAL_GALLEON, # C: 갈레온
      "",              # D: 아이템
      "",              # E: 메모
      "",              # F: 기숙사
      "",              # G: 마지막베팅일
      "",              # H: 오늘베팅횟수
      "",              # I: 출석날짜
      "",              # J: 마지막타로일
      0                # K: 개별 기숙사 점수
    ]
    @sheet_manager.append('사용자', user_row)
    puts "[입학] 사용자 등록 완료: #{@sender} (#{@name})"

    # 2단계: 스탯 시트 등록 (전투봇 연동)
    stat_row = [
      @sender, # A: ID
      @name,   # B: 이름
      100,     # C: HP
      5,       # D: 민첩
      5,       # E: 행운
      5,       # F: 공격
      5        # G: 방어
    ]
    @sheet_manager.append('스탯', stat_row)
    puts "[입학] 스탯 초기값 등록 완료: #{@sender}"

    # 3단계: 조사상태 시트 등록
    investigate_row = [
      @sender,   # A: 사용자 ID
      "없음",    # B: 조사상태
      "-",       # C: 위치
      "0",       # D: 이동포인트
      "0",       # E: 은밀도
      "-"        # F: 협력상태
    ]
    @sheet_manager.append('조사상태', investigate_row)
    puts "[입학] 조사상태 초기값 등록 완료: #{@sender}"

    # 4단계: 환영 메시지
    @mastodon_client.reply(@status, "#{@name} 학생, 호그와트에 온 걸 환영해요.")

  rescue => e
    puts "[에러] 입학 처리 중 오류: #{e.message}"
    puts e.backtrace.first(5)
    @mastodon_client.reply(@status, "입학 처리 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.")
  end
end
