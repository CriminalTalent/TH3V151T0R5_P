#!/bin/bash
# PM2 교수봇 관리 스크립트

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

case "$1" in
  start)
    echo "🚀 교수봇 시작 중..."
    pm2 start ecosystem.config.js
    pm2 save
    ;;
    
  stop)
    echo "⏹️  교수봇 정지 중..."
    pm2 stop professor-bot
    ;;
    
  restart)
    echo "🔄 교수봇 재시작 중..."
    pm2 restart professor-bot
    ;;
    
  reload)
    echo "♻️  교수봇 무중단 재시작 중..."
    pm2 reload professor-bot
    ;;
    
  status)
    echo "📊 교수봇 상태:"
    pm2 show professor-bot
    ;;
    
  logs)
    echo "📜 교수봇 로그:"
    pm2 logs professor-bot --lines 100
    ;;
    
  monitor)
    echo "📈 교수봇 모니터링:"
    pm2 monit
    ;;
    
  delete)
    echo "🗑️  교수봇 프로세스 삭제 중..."
    pm2 delete professor-bot
    ;;
    
  setup)
    echo "⚙️  PM2 초기 설정 중..."
    
    # 로그 디렉토리 생성
    mkdir -p logs
    
    # PM2 시작
    pm2 start ecosystem.config.js
    
    # 부팅 시 자동 시작 설정
    pm2 startup
    echo ""
    echo "위에 표시된 명령어를 복사해서 실행하세요."
    echo "그 후 'pm2 save'를 실행하세요."
    ;;
    
  *)
    echo "교수봇 PM2 관리 스크립트"
    echo ""
    echo "사용법: $0 {command}"
    echo ""
    echo "명령어:"
    echo "  setup    - PM2 초기 설정 (최초 1회)"
    echo "  start    - 봇 시작"
    echo "  stop     - 봇 정지"
    echo "  restart  - 봇 재시작"
    echo "  reload   - 봇 무중단 재시작"
    echo "  status   - 봇 상태 확인"
    echo "  logs     - 봇 로그 보기"
    echo "  monitor  - 실시간 모니터링"
    echo "  delete   - 봇 프로세스 삭제"
    echo ""
    exit 1
    ;;
esac
