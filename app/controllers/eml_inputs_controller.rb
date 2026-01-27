# frozen_string_literal: true

class EmlInputsController < ApplicationController
  # デモ用: Web フォームから EML を Verbena API に投入する

  def new
    @fields_values = {}
    @upload_values = {}
  end

  def create
    mode = params[:input_mode].to_s.presence || 'fields'

    case mode
    when 'upload'
      response = handle_upload_mode!
    else
      response = handle_fields_mode!
    end

    flash[:notice] = "送信しました (status #{response.code})"
    redirect_to new_eml_input_path
  rescue => ex
    Rails.logger.error("eml_inputs#create error: #{ex.class}: #{ex.message}")
    flash.now[:alert] = "送信に失敗しました: #{ex.message}"

    # エラー時は入力値を保持して再表示
    raw_fields = params[:fields] || {}
    raw_upload = params[:upload] || {}

    @fields_values = if raw_fields.respond_to?(:permit!)
                       raw_fields.permit!.to_h.symbolize_keys
                     else
                       raw_fields.to_h.symbolize_keys
                     end

    @upload_values = if raw_upload.respond_to?(:permit!)
                       raw_upload.permit!.to_h.symbolize_keys
                     else
                       raw_upload.to_h.symbolize_keys
                     end

    render :new, status: :unprocessable_entity
  end

  private

  def handle_fields_mode!
    attrs = fields_params
    validate_token!(attrs[:token])

    mail = Mail.new
    mail.to = split_addresses(attrs[:to])
    mail.cc = split_addresses(attrs[:cc])
    mail.bcc = split_addresses(attrs[:bcc])

    [:from, :subject, :body].each do |key|
      mail.public_send("#{key}=", attrs[key]) if attrs[key].present?
    end

    # ここで日時を設定してEML化する
    mail.date = parsed_time_or_now(attrs[:sent_at])
    # EML生成時にBCCを含めるため、ここで明示的にヘッダー出力を有効化する
    mail[:bcc].include_in_headers = true if mail[:bcc]

    # EML(String)として共通処理へ渡す
    process_eml_delivery!(mail.to_s, attrs[:sent_at], attrs[:token])
  end

  def handle_upload_mode!
    attrs = upload_params
    validate_token!(attrs[:token])

    upload = attrs[:eml_file]
    raise ArgumentError, 'EMLファイルを選択してください' unless upload.present?

    eml = upload.respond_to?(:read) ? upload.read : upload.to_s
    raise ArgumentError, 'EMLが空です' if eml.blank?

    # EML(String)として共通処理へ渡す
    process_eml_delivery!(eml, attrs[:sent_at], attrs[:token])
  end

  def process_eml_delivery!(eml_source, sent_at_param, token)
    mail = Mail.new(eml_source)

    if sent_at_param.present?
      mail.date = parsed_time_or_nil(sent_at_param)
    end

    mail[:bcc].include_in_headers = true if mail[:bcc]
    deliver_via_api!(mail, token)
  end

  def validate_token!(token)
    raise ArgumentError, 'Tokenを入力してください' if token.blank?
  end

  def deliver_via_api!(mail, token)
    mail.delivery_method(Verbena::HttpDelivery, delivery_settings(token))
    mail.deliver!
  end

  def delivery_settings(token)
    {
      url_enqueue: endpoint_url,
      access_token: token,
      logger: Rails.logger,
      return_response: true,
      # 開発時は以下のように false を指定して検証を無効化することも可能です
      # verify_ssl: false
    }
  end

  def endpoint_url
    env_url = ENV['VERBENA_API_ENDPOINT_URL'].to_s.strip
    return env_url unless env_url.blank?

    # 【実装時の注意点: デモ用コードとしての背景】
    # このコードは「Verbenaを利用する外部システム」の実装サンプルですが、
    # デモ環境の都合上、APIサーバー(Verbena)と同じコンテナ内で動作しています。
    #
    # 通常、外部システムからは正式なAPIのURL(https://api.example.com など)を設定しますが、
    # ここでは設定がない場合のフォールバックとして「自分自身(localhost)」を指しています。
    #
    # 1. request.base_url を使わない理由:
    #    これは「ブラウザから見たURL(例: Port 23000 / https)」を返しますが、
    #    コンテナ内部のプロセス間通信は `http://127.0.0.1:3000` で行われるため、
    #    外向けの情報をそのまま使うと接続できません。
    #
    # 2. http スキーム固定の理由:
    #    外部アクセスが HTTPS でも、コンテナ内部は HTTP で待受けるのが一般的(SSLオフロード)です。
    #
    # Rails自体にはリッスンポートを知る標準APIがないため、
    # 慣習的に PORT 環境変数かデフォルトの 3000 を使用します
    port = ENV['PORT'].presence || 3000
    "http://127.0.0.1:#{port}/api/v1/mail_queues"
  end

  def parsed_time_or_now(raw)
    return Time.current if raw.blank?

    Time.zone.parse(raw)
  rescue
    Time.current
  end

  def parsed_time_or_nil(raw)
    return nil if raw.blank?

    Time.zone.parse(raw)
  rescue
    nil
  end

  def split_addresses(raw)
    return [] if raw.blank?

    # Mail::AddressList を使用して安全にアドレスのみを抽出する
    Mail::AddressList.new(raw.to_s).addresses.map(&:address)
  rescue Mail::Field::ParseError => e
    # パースエラーの場合は意図しない送信を防ぐため例外とする
    raise ArgumentError, "不正なメールアドレス形式が含まれています: #{raw} (#{e.message})"
  end

  def fields_params
    params.require(:fields).permit(:to, :cc, :bcc, :from, :subject, :body, :token, :sent_at)
  end

  def upload_params
    params.require(:upload).permit(:eml_file, :token, :sent_at)
  end
end
