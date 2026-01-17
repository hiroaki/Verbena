# 使い方：
#
#   # MailQueue ID を指定して1件処理する（ActiveJob経由で呼び出される想定）
#   Verbena::DeliveryService.new.perform_one(mail_queue)
#
module Verbena
  class DeliveryService < ServiceBase
    include DeliveryHelper

    # 変更不可
    attr_reader :job_id

    def initialize(options = {})
      super

      # job_id はログ出力のトレーサビリティのために使用します
      @job_id = options[:job_id]
    end

    # mail_queue のメールを送信し、結果をテーブル delivery_responses に記録します。
    # 送信時に例外が発生した際は、レスポンスコード 451 としています。
    # ネットワークエラーや4xxエラーの場合は、ログ記録後に例外を再発生させ、ジョブのリトライに委ねます。
    def perform_one(mail_queue)
      res = mail_queue.delivery_responses.new(responded_at: Time.current)

      error_to_raise = nil
      loglevel = :info
      message = nil

      begin
        send_mail!(mail_queue) do |mail, response|
          res.message_id = mail.message_id
          res.status = response.status
          # string が列の幅を超えると ActiveRecord::ValueTooLong ですので、明示的に切り詰めてこれを避けます。
          # 通常はもっと短い文章です。
          res.contents = response.string.chomp.truncate(250)

          if response.status.to_s.start_with?('2')
            # Success
            message = structured_log(
              event: 'deliver.result', level: 'info', job_id: job_id,
              mail_queue_id: mail_queue.id, message_id: res.message_id, smtp_status: res.status,
              message: "OK sending a message mail_queues.id=[#{mail_queue.id}] Message-ID=<#{mail.message_id}>, response: status=[#{res.status}] string=[#{res.contents}]"
            )
            loglevel = :info
          elsif response.status.to_s.start_with?('4')
             # 4xx Error: Retryable
             message = structured_log(
              event: 'deliver.result', level: 'error', job_id: job_id,
              mail_queue_id: mail_queue.id, message_id: res.message_id, smtp_status: res.status,
              message: "NG (Retryable) sending a message mail_queues.id=[#{mail_queue.id}] Message-ID=<#{mail.message_id}>, response: status=[#{res.status}] string=[#{res.contents}]"
            )
            loglevel = :error
            # Raise exception to trigger job retry
            error_to_raise = Net::SMTPServerBusy.new(response.string)
          else
            # 5xx or others: Failure (Non-retryable)
            message = structured_log(
              event: 'deliver.result', level: 'error', job_id: job_id,
              mail_queue_id: mail_queue.id, message_id: res.message_id, smtp_status: res.status,
              message: "NG (Fatal) sending a message mail_queues.id=[#{mail_queue.id}] Message-ID=<#{mail.message_id}>, response: status=[#{res.status}] string=[#{res.contents}]"
            )
            loglevel = :error
          end
        end
      rescue => ex
        loglevel = :error
        message = structured_log(
          event: 'deliver.exception', level: 'error', job_id: job_id,
          mail_queue_id: mail_queue.id, smtp_status: 451,
          error: "#{ex.class}: #{ex.message}", message: "NG sending a message mail_queues.id=[#{mail_queue.id}]: #{ex.inspect}"
        )

        res.status = 451 # "Requested action aborted: local error in processing"

        # Determine if it's a permanent failure based on exception type
        if ex.is_a?(Net::SMTPSyntaxError)
          res.status = 501 # Syntax error in parameters or arguments
        elsif ex.is_a?(Net::SMTPFatalError)
          res.status = 554 # Transaction failed (or 5.0.0 Unable to process SMTP response)
        end

        res.contents = ex.inspect

        if retryable_error?(ex)
          error_to_raise = ex
        end
      ensure
        logger.send(loglevel, message)

        if res.save
          logger.info(structured_log(event: 'delivery_response.created', level: 'info', job_id: job_id, mail_queue_id: mail_queue.id, message_id: res.message_id, smtp_status: res.status, message: "CREATED DeliveryResponse #{res.id}"))
        else
          logger.error(structured_log(event: 'delivery_response.create_failed', level: 'error', job_id: job_id, mail_queue_id: mail_queue.id, message_id: res.message_id, smtp_status: res.status, error: res.errors.inspect, message: 'FAILED to create DeliveryResponse'))
        end
      end

      raise error_to_raise if error_to_raise
    end

    # mail_queue のメールを送信します。
    def send_mail!(mail_queue, &block)
      mail = create_mail_message(mail_queue.eml)
      mail.smtp_envelope_from(mail_queue.envelope_from)
      mail.smtp_envelope_to(mail_queue.envelope_to)

      response = mail.deliver!
      # Mail::TestMailer や :file の場合、Net::SMTP::Response を返さないため合成します。
      unless response.is_a?(Net::SMTP::Response)
        response = Net::SMTP::Response.parse('250 OK (synthetic by Verbena)')
      end

      if block_given?
        yield mail, response
      else
        [mail, response]
      end
    end

    private


    def retryable_error?(ex)
      DeliveryJob.retryable_error?(ex)
    end
  end
end
