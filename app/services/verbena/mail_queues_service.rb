module Verbena
  class MailQueuesService < ServiceBase
    class NoRecipientsError < StandardError; end

    def initialize(options = {})
      super
    end

    # :nocov:
    # for develop
    def attach_files_to_eml(eml, *files)
      Mail.read(eml).tap do |message|
        files.each do |file|
          message.add_file(file)
        end
      end
    end
    # :nocov:

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
    def create_mail_queue_with_envelope!(eml, envelope_from, envelope_to, timer_at)
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
  end
end
