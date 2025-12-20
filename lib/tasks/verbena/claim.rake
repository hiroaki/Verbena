namespace :verbena do
  namespace :claim do
    desc 'スタック（長時間 claim されているが配送されていない）mail_queues の claim を解放する'
    task :release_stale, [:older_than_hours, :dry] => :environment do |_task, args|
      older_than_hours = args[:older_than_hours]&.to_f || 1.0
      older_than = older_than_hours.hours.ago
      dry_run = truthy?(args[:dry])
      
      # pluralize は整数値を使用して正しい複数形を生成
      hour_unit = 'hour'.pluralize(older_than_hours.round)
      if dry_run
        stale_count = MailQueue.where('claimed_at IS NOT NULL AND claimed_at < ?', older_than).count
        puts "DRY RUN: Would release #{stale_count} stale claims older than #{older_than_hours} #{hour_unit}"
        Rails.logger.info("[MailQueue] DRY RUN: Would release #{stale_count} stale claims")
      else
        stale_count = MailQueue.release_stale_claims!(older_than: older_than)
        puts "Released #{stale_count} stale claims older than #{older_than_hours} #{hour_unit}"
      end
    end

    desc '現在 claim されているが配送結果がないレコードを表示（スタック検出）'
    task :show_stale => :environment do
      stale_records = MailQueue.claimed_but_undelivered
                               .select('mail_queues.id, mail_queues.session_id, mail_queues.claimed_at, mail_queues.envelope_to, mail_queues.created_at')
                               .order(:claimed_at)
      
      if stale_records.any?
        puts "Found #{stale_records.size} claimed but undelivered records:"
        puts "ID\tSession ID\tClaimed At\tEnvelope To\tAge"
        puts "-" * 80
        
        stale_records.each do |record|
          age = record.claimed_at ? Time.current - record.claimed_at : 0
          age_str = format_duration(age)
          session_id_str = record.session_id ? "#{record.session_id[0..8]}..." : "(none)"
          puts "#{record.id}\t#{session_id_str}\t#{record.claimed_at}\t#{record.envelope_to}\t#{age_str}"
        end
      else
        puts "No stale claimed records found."
      end
    end
  end

  # Rake helper methods (local to this file)
  BOOLEAN_TYPE = ActiveModel::Type::Boolean.new

  def truthy?(val)
    # Rails-native boolean casting: true => 1,true,t,on,yes | false => 0,false,f,off,no
    BOOLEAN_TYPE.cast(val)
  end

  def format_duration(seconds)
    return "0s" if seconds < 1
    
    # 秒単位に丸める（小数部は破棄）
    hours = (seconds / 3600).to_i
    minutes = ((seconds % 3600) / 60).to_i
    secs = (seconds % 60).to_i
    
    parts = []
    parts << "#{hours}h" if hours > 0
    parts << "#{minutes}m" if minutes > 0 || hours > 0
    parts << "#{secs}s"
    
    parts.join("")
  end
end