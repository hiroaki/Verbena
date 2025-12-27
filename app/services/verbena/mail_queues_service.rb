module Verbena
  class MailQueuesService < ServiceBase
    include Verbena::EmlFileReader

    class NoRecipientsError < StandardError; end
    class NegativeAgeError < StandardError; end
    class NegativeClaimHoursError < StandardError; end

    def initialize(options = {})
      super
    end

    # ファイルパス path から EML形式のファイルを読み込み、MailQueue レコードを作成します。
    # 作成した MailQueue のリストを返します。
    def create_mail_queues_from_file!(path)
      eml = read_eml_from_file!(path)
      create_mail_queues_by_eml!(eml)
    end

    # ファイルパス path から EML形式のファイルを読み込み、明示的なエンベロープ値で MailQueue を作成します。
    # 作成した MailQueue を返します。
    def create_mail_queue_from_file_with_envelope!(path, envelope_from, envelope_to, timer_at = nil)
      eml = read_eml_from_file!(path)
      create_mail_queue_with_envelope!(eml, envelope_from, envelope_to, timer_at)
    end

    # EML 形式のメールデータ eml （文字列）をもとに、 MailQueue （および関連する EmlSource ）を作成します。
    # eml に含まれる宛先のアドレスの数だけレコードが作成されます。
    #
    # 作成されるレコードの envelope_from は、 Mail::Message#smtp_envelope_from の仕様に基づき、
    # eml の (a) Return-path: (b) Sender: (c) From: の最初の値、の順で最初に見つかったのものが使用されます。
    # またレコードの timer_at は、その時刻になるまでは配送しないように配送プログラムに指示するもので、
    # eml の Date: フィールドの値が使用されます。
    # ただしこの段階の eml については Date: フィールドは省略可能で（ RFC 5322 では Date: は必須です）、
    # 省略されている場合は timer_at に現在時刻を使用します。
    #
    # 作成した MailQueue のリストを返します。
    def create_mail_queues_by_eml!(eml)
      message = Mail.new(eml)
      destinations = Array(message.destinations).uniq
      if destinations.empty?
        raise NoRecipientsError, 'no recipients'
      end

      envelope_from = Verbena::Settings.envelope_from_override.presence || message.smtp_envelope_from
      timer_at = message.date || Time.current

      mail_queues = []
      MailQueue.transaction do
        eml_source = EmlSource.create!(eml: eml)

        destinations.each do |envelope_to|
          mail_queues << eml_source.mail_queues.create!(
            timer_at: timer_at,
            envelope_from: envelope_from,
            envelope_to: envelope_to,
          )
        end
      end

      mail_queues
    end

    # envelope を指定して MailQueue （および関連する EmlSource ）を作成します。
    # 作成した MailQueue を返します。
    def create_mail_queue_with_envelope!(eml, envelope_from, envelope_to, timer_at = nil)
      if timer_at.nil?
        message = Mail.new(eml)
        timer_at = message.date || Time.current
      end

      MailQueue.transaction do
        eml_source = EmlSource.create!(eml: eml)
        eml_source.mail_queues.create!(
          timer_at: timer_at,
          envelope_from: envelope_from,
          envelope_to: envelope_to,
        )
      end
    end

    #
    def destroy_mail_queue_by_id!(id)
      destroy_mail_queue!(MailQueue.find(id))
    end

    #
    def destroy_mail_queue!(mail_queue)
      mail_queue.destroy!
    end

    # スタック（長時間 claim されているが配送されていない）mail_queues の claim を解放する
    #
    # @param older_than_hours [Float] この時間より前に claim されたレコードを対象とする（時間単位）
    # @param dry_run [Boolean] true の場合、実際には解放せず、対象レコード数のみ返す
    # @return [Integer] 解放されたレコード数（dry_run の場合は対象レコード数）
    def release_stale_claims(older_than_hours: 1.0, dry_run: false)
      hours = self.class.normalize_hours_arg(older_than_hours)
      raise NegativeClaimHoursError, 'older_than_hours must be >= 0' if hours.negative?
      older_than = hours.hours.ago

      relation = MailQueue.stale_claims_relation(older_than: older_than)

      if dry_run
        count = relation.count
        logger.info(structured_log(
          event: 'mail_queues.dry_run',
          level: 'info',
          session_id: nil,
          mail_queue_id: nil,
          message: "DRY RUN: #{count} stale claims would be released (older than #{hours} hours as of #{older_than})"
        ))
        count
      else
        count = relation.update_all(session_id: nil, claimed_at: nil, updated_at: Time.current)
        logger.info(structured_log(
          event: 'mail_queues.release',
          level: 'info',
          session_id: nil,
          mail_queue_id: nil,
          message: "Released #{count} stale claims older than #{hours} hours (as of #{older_than})"
        ))
        count
      end
    end

    # 現在 claim されているが配送結果がないレコードの情報を取得する
    #
    # @return [Array<Hash>] スタックレコードの情報配列
    # @raise [NegativeAgeError] claimed_at が未来の場合（age_secondsが負の場合）
    #   → システム時刻の不整合やデータ不整合が疑われるため例外を投げます。
    def show_stale_claims
      stale_records = MailQueue.claimed_but_undelivered
                               .select('mail_queues.id, mail_queues.session_id, mail_queues.claimed_at, mail_queues.envelope_to')
                               .order(:claimed_at)

      now = Time.current
      stale_records.map do |record|
        age = record.claimed_at ? now - record.claimed_at : 0
        if age < 0
          raise NegativeAgeError, "Negative age_seconds detected for MailQueue id=#{record.id} (claimed_at=#{record.claimed_at}, now=#{now})"
        end

        {
          id: record.id,
          session_id: record.session_id,
          claimed_at: record.claimed_at,
          envelope_to: record.envelope_to,
          age_seconds: age
        }
      end
    end

    def self.normalize_hours_arg(val)
      return 1.0 if val.nil? || val.to_s.strip.empty?
      Float(val)
    end
  end
end
