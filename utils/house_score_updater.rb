# utils/house_score_updater.rb (통합 버전)
module HouseScoreUpdater
  module_function

  # =====================================================
  # 기숙사 점수 갱신 (통합 시스템)
  # =====================================================
  def update_house_scores(sheet_manager)
    puts "[기숙사 점수] 통합 동기화 시작..."
    
    begin
      result = sheet_manager.sync_house_system
      
      if result[:success]
        puts "[기숙사 점수] 동기화 성공!"
        result[:house_totals].each do |house, score|
          puts "  - #{house}: #{score}점"
        end
      else
        puts "[기숙사 점수] 동기화 실패: #{result[:error]}"
      end
      
      result[:success]
      
    rescue NoMethodError => e
      # sheet_manager에 sync_house_system이 없는 경우 기존 방식 사용
      puts "[기숙사 점수] 레거시 방식으로 갱신..."
      update_house_scores_legacy(sheet_manager)
    rescue => e
      puts "[오류] 기숙사 점수 갱신 실패: #{e.message}"
      puts e.backtrace.first(3)
      false
    end
  end

  # =====================================================
  # 레거시 방식 (기존 코드 백업)
  # =====================================================
  def update_house_scores_legacy(sheet_manager)
    puts "[기숙사 점수] 레거시 갱신 시작..."
    
    begin
      # 1단계: 사용자 시트에서 개별 기숙사 점수 집계
      user_range = "사용자!A:K"
      user_values = sheet_manager.read_values(user_range)
      
      if user_values.nil? || user_values.empty?
        puts "[경고] 사용자 시트가 비어있습니다."
        return false
      end

      house_totals = Hash.new(0)
      
      user_values[1..].each do |row|
        next if row.nil? || row[0].nil?
        
        house = (row[5] || "").to_s.strip
        individual_score = (row[10] || 0).to_i
        
        # 날짜 형식이거나 빈 값은 제외
        next if house.empty? || house =~ /^\d{4}-\d{2}-\d{2}$/
        
        house_totals[house] += individual_score
      end

      puts "[기숙사 점수] 집계 완료: #{house_totals.inspect}"

      # 2단계: 기숙사 시트 업데이트
      house_range = "기숙사!A:B"
      house_values = sheet_manager.read_values(house_range)
      
      if house_values.nil? || house_values.empty?
        puts "[경고] 기숙사 시트가 비어있습니다."
        return false
      end

      # 3단계: 기숙사 시트 업데이트
      house_values[1..].each_with_index do |row, idx|
        next if row.nil? || row[0].nil?
        
        house_name = row[0].to_s.strip
        new_score = house_totals[house_name] || 0
        row_num = idx + 2
        
        range = "기숙사!B#{row_num}"
        sheet_manager.update_values(range, [[new_score]])
        
        puts "[기숙사 점수] #{house_name}: #{new_score}점 반영"
      end

      puts "[기숙사 점수] 레거시 갱신 완료"
      true
      
    rescue => e
      puts "[오류] 레거시 갱신 실패: #{e.message}"
      puts e.backtrace.first(3)
      false
    end
  end
end
