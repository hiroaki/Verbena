module Api
  module V1
    class MailQueuesController < ApplicationController
      before_action :prepare_mail_queue, only: [:show, :update, :destroy]
      before_action :prepare_and_validate_eml!, only: [:create]

      attr_accessor :mail_queue

      # api_v1_mail_queues GET /api/v1/mail_queues
      def index
        # Start from a projected relation (no eager load, no evaluation yet)
        scope = MailQueue.select(:id, :timer_at, :envelope_from, :envelope_to, :eml_source_id, :created_at, :updated_at)
        # Minimal order support per OSS_TODO: default id desc; accept only "id asc" or "id desc"
        scope = apply_order(scope)
        # Apply pagination at the DB level (still lazy until render)
        scope = scope.offset(pagination_offset).limit(pagination_limit)
        render json: scope
      end

      # api_v1_mail_queues POST /api/v1/mail_queues
      def create
        mail_queues = Verbena::MailQueuesService.new.create_mail_queues_by_eml!(@eml_string)
        render json: { message: 'ok', ids: mail_queues.map(&:id) }, status: :ok
      rescue Verbena::MailQueuesService::NoRecipientsError
        render_error('no_recipients', 'no recipients', :unprocessable_entity)
      rescue => ex
        render_error('unprocessable_entity', ex.message, :unprocessable_entity)
      end

      # api_v1_mail_queue GET /api/v1/mail_queues/:id
      def show
        render json: serialize_mail_queue(mail_queue)
      end

      # api_v1_mail_queue PATCH|PUT /api/v1/mail_queues/:id
      def update
        # mail_queue.assign_attributes(mail_queue_params)
        #
        # if mail_queue.invalid?
        #   render json: mail_queue.errors, status: :unprocessable_entity
        # else
        #   mail_queue.save!
        #   render json: mail_queue, status: :ok
        # end

        # TODO: 基本的に MailQueue の更新は受け付けず、
        # 更新したい場合は削除して新しいレコードを作る方針ですが、再考の余地はあります
        render json: { message: 'forbidden' }, status: :forbidden
      end

      # api_v1_mail_queue DELETE /api/v1/mail_queues/:id
      def destroy
        Verbena::MailQueuesService.new.destroy_mail_queue!(mail_queue)
        render json: { message: 'ok' }, status: :ok
      end

      private

        def apply_order(scope)
          order_param = params[:order].to_s.strip.downcase
          case order_param
          when 'id asc'
            scope.order(id: :asc)
          when 'id desc'
            scope.order(id: :desc)
          else
            scope.order(id: :desc)
          end
        end

        def prepare_mail_queue
          @mail_queue = MailQueue.find(params[:id])
        rescue ActiveRecord::RecordNotFound => ex
          render_error('not_found', 'resource not found', :not_found)
        end

        def mail_queue_params
          params.require(:mail_queue).permit(
            :eml,
          )
        end

        def mail_queue_param_eml
          eml = mail_queue_params[:eml]
          if eml.respond_to?(:read)
            eml.read
          else
            eml.to_s
          end
        end

        # Validate EML payload size and store a validated string for create action
        def prepare_and_validate_eml!
          eml = mail_queue_param_eml
          max = Verbena::Settings.eml_max_bytes
          if eml.bytesize > max
            render_error('eml_too_large', "eml size exceeds limit (#{max} bytes)", :unprocessable_entity)
            return
          end
          @eml_string = eml
        end

        def include_responses_latest?
          params[:include].to_s.strip.downcase == 'responses:latest'
        end

        def include_responses?
          params[:include].to_s.strip.downcase == 'responses'
        end

        def serialize_mail_queue(mq)
          base = mq.as_json(only: [:id, :timer_at, :envelope_from, :envelope_to, :eml_source_id, :created_at, :updated_at])
          if include_responses_latest?
            latest = responses_relation(mq).limit(1)
            base["responses"] = latest.as_json(only: [:id, :status, :contents, :message_id, :responded_at, :created_at, :updated_at])
          elsif include_responses?
            limited = responses_relation(mq).limit(responses_limit)
            base["responses"] = limited.as_json(only: [:id, :status, :contents, :message_id, :responded_at, :created_at, :updated_at])
          end
          base
        end

        def responses_relation(mq)
          mq.delivery_responses.order(responded_at: :desc)
        end

        def responses_limit
          raw = params[:responses_limit].to_i
          return Verbena::Settings.api_responses_default_limit if raw <= 0
          [raw, Verbena::Settings.api_responses_limit_cap].min
        end

      public
    end
  end
end
