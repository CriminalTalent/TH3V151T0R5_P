# cron_tasks/midnight_reset.rb
require 'date'

def run_midnight_reset(sheet_manager, mastodon_client)
  puts "[자정 초기화] 시작 - #{Time.now}"
  
  begin
    # 전투봇용 사용자 시트 읽기
    values = sheet_manager.read_values("사용자!A:Z")
    return if values.nil? || values.empty?
    
    header = values[0]
    puts "[자정 초기화] 헤더: #{header.inspect}"
    
    # 열 인덱스 찾기
    # 베팅 횟수: H열 (7), 체력: (찾아야 함)
    bet_count_col = 7  # H열 - 오늘베팅횟수
    hp_col = header.index { |h| h.to_s =~ /체력|HP/i }
    
    if hp_col.nil?
      puts "[자정 초기화] 경고: 체력 열을 찾을 수 없습니다."
    end
    
    reset_count = 0
    
    values[1..].each_with_index do |row, idx|
      next if row.nil? || row[0].nil?
      
      user_id = row[0].to_s.strip
      sheet_row = idx + 2  # Google Sheets 행 번호
      
      needs_update = false
      updates = []
      
      # 베팅 횟수 초기화 (3회 -> 0회)
      current_bet_count = (row[bet_count_col] || 0).to_i
      if current_bet_count > 0
        range = "사용자!H#{sheet_row}"
        sheet_manager.update_values(range, [[0]])
        updates << "베팅횟수 #{current_bet_count}→0"
        needs_update = true
      end
      
      # 체력 완전 회복 (현재 체력 -> 100)
      if hp_col
        current_hp = (row[hp_col] || 100).to_i
        if current_hp < 100
          column_letter = ('A'.ord + hp_col).chr
          range = "사용자!#{column_letter}#{sheet_row}"
          sheet_manager.update_values(range, [[100]])
          updates << "체력 #{current_hp}→100"
          needs_update = true
        end
      end
      
      if needs_update
        puts "[자정 초기화] #{user_id}: #{updates.join(', ')}"
        reset_count += 1
      end
    end
    
    puts "[자정 초기화] 완료 - #{reset_count}명 초기화됨"
    
    # 초기화 완료 알림 (선택사항)
    # mastodon_client.broadcast("자정이 되어 베팅 횟수와 체력이 초기화되었습니다.")
    
  rescue => e
    puts "[자정 초기화 오류] #{e.message}"
    puts e.backtrace.first(3)
  end
end
