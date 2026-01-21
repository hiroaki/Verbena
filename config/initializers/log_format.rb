# Configure log formatter based on VERBENA_LOG_FORMAT
#
# - VERBENA_LOG_FORMAT=text (default): keep Rails default formatter
# - VERBENA_LOG_FORMAT=json: structure logs as JSON with fixed keys
#
# Keys (when possible):
#   event, level, timestamp, job_id, mail_queue_id, message_id, smtp_status, error, message

require 'json'

module Verbena
  class JsonLogFormatter < ::Logger::Formatter
    # Support Rails tagged logging API (adds #tagged, #push_tags, etc.)
    include ActiveSupport::TaggedLogging::Formatter

    # Render a JSON line
    def call(severity, time, _progname, msg)
      base = {
        level: severity.to_s.downcase,
        timestamp: (time.respond_to?(:utc) ? time.utc : time).iso8601,
      }

      payload = case msg
                when Hash
                  # stringify keys to be explicit and stable
                  msg.transform_keys(&:to_s)
                else
                  { 'message' => msg2str(msg) }
                end

      JSON.generate(base.merge(payload)) + "\n"
    rescue => e
      # Fallback to a minimal JSON when unexpected object is passed
      JSON.generate(level: severity.to_s.downcase, timestamp: Time.now.utc.iso8601, message: "log-format-error: #{e.class}: #{e.message}") + "\n"
    end
  end
end

# NOTE: フォーマッタ適用のタイミングについて
# - ここでは `Rails.application.config.to_prepare` を使っています。
#   - 理由1: 環境別設定（production.rb など）でロガーやフォーマッタが上書きされ得るため、
#            最終段階で JSON フォーマッタを適用する意図です。
#   - 理由2: 開発環境のコードリロード時にも毎回実行され、
#            ローダや再設定の影響後にフォーマッタが確実に再適用されます。
# - `application.rb` 側は「色（colorize_logging）の有効/無効」を ENV に応じて一元管理し、
#   こちらの初期化子は「実体フォーマッタの差し替え」に専念します。
# - テスト環境では既存スペックの期待（文字列ログ）を維持するため、
#   JSON フォーマッタの適用を明示的に除外しています（JSON 形式の検証はフォーマッタの単体テストで担保）。
Rails.application.config.to_prepare do
  format = ENV['VERBENA_LOG_FORMAT'].to_s.strip.downcase
  # Do not switch to JSON formatter in test env to keep specs stable
  if format == 'json' && !Rails.env.test?
    formatter = Verbena::JsonLogFormatter.new
    # Apply to Rails logger
    Rails.logger.formatter = formatter if Rails.logger.respond_to?(:formatter=)
    # Also apply to ActiveRecord logger if present
    if defined?(ActiveRecord) && ActiveRecord::Base.logger && ActiveRecord::Base.logger.respond_to?(:formatter=)
      ActiveRecord::Base.logger.formatter = formatter
    end
  end
end
