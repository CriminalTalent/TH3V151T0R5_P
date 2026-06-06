# 🧙 교수님 봇 (Professor Bot)

마스토돈 기반 마법학교 커뮤니티에서 운영되는  
**출석 · 과제 · 기숙사 점수 관리 자동화 봇**입니다.  
Google 스프레드시트와 연동되어 유저 상태를 기록하고,  
정해진 시간에 교수님 스타일의 다정한 멘트로 학생들을 안내합니다.

---

## ✨ 기능 요약

| 명령어           | 기능 설명 |
|------------------|-----------|
| `[입학/이름]`     | 새로운 유저 등록 및 초기 갈레온 20 지급 |
| `[출석]`         | 하루 1회 가능. 출석 시 2갈레온 + 기숙사 점수 1점 |
| `[과제]`         | 과제 제출 1회 당 5갈레온 + 기숙사 점수 3점 |
| `[주머니]`       | 현재 갈레온 및 아이템 상태 확인 (옵션) |

모든 명령은 마스토돈 멘션 기반으로 작동합니다.  
예: `@professorbot [출석]`

---

## 📁 프로젝트 구조

├── main.rb # 실행 진입점
├── scheduler.rb # 자동 푸시 스케줄러
├── sheet_manager.rb # Google Sheet 핸들러
├── mastodon_client.rb # 마스토돈 API 래퍼
├── professor_command_parser.rb # 교수봇 커맨드 파서
├── commands/
│ ├── enroll_command.rb
│ ├── attendance_command.rb
│ └── homework_command.rb
├── utils/
│ ├── weather_message.rb
│ ├── house_score_updater.rb
│ └── warm_advice.rb
├── cron_tasks/
│ ├── morning_attendance_push.rb
│ ├── evening_attendance_end.rb
│ ├── curfew_alert.rb
│ └── curfew_release.rb
├── push_notifier.rb
├── .env
├── Gemfile
└── config.json # Google API 인증 정보

yaml
복사
편집

---

## 🔧 설치 및 실행 방법

### 1. 의존성 설치

```bash
bundle install
2. 환경변수 설정
.env 파일 생성 후 다음 내용 추가:

dotenv
복사
편집
MASTODON_BASE_URL=https://eclyria.pics
MASTODON_TOKEN=your_token_here
GOOGLE_SHEET_ID=your_sheet_id_here
GOOGLE_CREDENTIALS_PATH=config.json
3. 실행
수동 명령어 반응 실행:
bash
복사
편집
ruby main.rb
자동 푸시 (출석 알림, 통금 등):
bash
복사
편집
ruby scheduler.rb
🕰 자동 푸시 스케줄
시간	기능
07:00	아침 출석 안내
10:00	출석 마감
02:00	새벽 통금 알림
06:00	통금 해제 알림

→ 이 동작들은 모두 cron_tasks/ 디렉토리에 정의되어 있습니다.
→ 실제 활성화 여부는 스프레드시트의 교수 탭에서 ON/OFF로 설정합니다.

💬 교수님 톤 설정
모든 응답은 교수님의 인자하고 따뜻한 말투로 구성됩니다.
예시 응답:

출석을 확인했습니다. 오늘도 잘 시작하셨습니다.

“하루하루가 당신을 더 나은 마법사로 이끌어줄 거예요.”

🧠 스프레드시트 구조 요약
✅ 시트: 사용자
열	필드명	설명
A	ID	마스토돈 계정 (@user@server)
B	이름	캐릭터명 또는 닉네임
C	갈레온	정수
F	기숙사	사용자 기숙사명
I	출석날짜	마지막 출석일 (YYYY-MM-DD)
K	과제날짜	마지막 과제일 (YYYY-MM-DD)

✅ 시트: 교수
항목	설명
출석기능	전체 작동 여부 (ON/OFF)
아침 출석 자동툿	자동 푸시 여부
통금 해제 알람	통금 해제 푸시 여부

✅ 시트: 기숙사
열	필드명	설명
A	기숙사명	고유 이름
B	점수	누적 점수 (정수)

🤝 기여 및 확장
명령어 추가는 commands/ 폴더에 Ruby 클래스로 정의

자동 푸시는 cron_tasks/에 run_XXX 함수로 작성

날씨 메시지나 조언 메시지는 utils/ 에서 관리
