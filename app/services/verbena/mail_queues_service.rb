module Verbena
  class MailQueuesService < ServiceBase
    include Verbena::EmlFileReader

    class NoRecipientsError < StandardError; end

    # @param options [Hash]
    # @option options [Token] :token (Required) 操作の主体となる Token オブジェクト。
    #   このサービス内では、この Token に紐づく MailQueue のみを作成・操作します。
    #   Note: Service内ではTokenの有効期限チェック(active?)は行いません。
    #   呼出元(Controller, Rake task)の責任で有効なTokenを渡してください。
    def initialize(options = {})
      super
      @token = options[:token]
      raise ArgumentError, "Token is required for this service" if @token.nil?
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
          # @token.mail_queues 経由で作成して紐付けを保証
          mq = @token.mail_queues.create!(
            eml_source: eml_source,
            timer_at: timer_at,
            envelope_from: envelope_from,
            envelope_to: envelope_to,
          )
          mail_queues << mq
          enqueue_delivery_job(mq)
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
        # @token.mail_queues 経由で作成して紐付けを保証
        mq = @token.mail_queues.create!(
          eml_source: eml_source,
          timer_at: timer_at,
          envelope_from: envelope_from,
          envelope_to: envelope_to,
        )

        enqueue_delivery_job(mq)
        mq
      end
    end

    # 指定された id の MailQueue レコードを削除します。
    #
    # @param id [Integer] 削除する MailQueue の ID
    # @return [MailQueue] 削除された MailQueue オブジェクト
    # @raise [ActiveRecord::RecordNotFound] 指定された id のレコードが存在しない場合、または現在のトークンに属していない場合
    def destroy_mail_queue_by_id!(id)
      # 現在のトークンに紐づくレコードのみを検索対象とする
      mail_queue = @token.mail_queues.find(id)
      destroy_mail_queue!(mail_queue)
    end

    # 指定された MailQueue レコードを削除します。
    #
    # @param mail_queue [MailQueue] 削除する MailQueue オブジェクト
    # @return [MailQueue] 削除された MailQueue オブジェクト
    def destroy_mail_queue!(mail_queue)
      mail_queue.destroy!
    end



    private

    def enqueue_delivery_job(mail_queue)
      if mail_queue.timer_at.present? && mail_queue.timer_at > Time.current
        DeliveryJob.set(wait_until: mail_queue.timer_at).perform_later(mail_queue.id)
      else
        DeliveryJob.perform_later(mail_queue.id)
      end
    end


  end
end
