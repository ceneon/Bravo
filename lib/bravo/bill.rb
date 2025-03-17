module Bravo
  class Bill
    attr_reader :client, :base_imp, :total
    attr_accessor :net, :doc_num, :iva_cond, :recipient_iva_cond,
      :documento, :concepto, :moneda,
      :due_date, :aliciva_id, :fch_serv_desde, :fch_serv_hasta,
      :body, :response

    def initialize(attrs = {})
      Bravo::AuthData.fetch

      @client = Savon.client(
        env_namespace: :soap,
        wsdl: Bravo.service_url,
        ssl_cert_key_file: Bravo.pkey,
        ssl_cert_file: Bravo.cert,
        ssl_verify_mode: :none,
        read_timeout: 90,
        open_timeout: 90,
        headers: {
          'Accept-Encoding' => 'gzip, deflate', 'Connection' => 'Keep-Alive'
        },
        log: Bravo.log?,
        log_level: :debug,
        namespaces: {xmlns: 'http://ar.gov.afip.dif.FEV1/'}
      )

      @body           = {'Auth' => Bravo.auth_hash}
      @net            = attrs[:net] || 0
      self.documento  = attrs[:documento] || Bravo.default_documento
      self.moneda     = attrs[:moneda]    || Bravo.default_moneda
      self.iva_cond   = attrs[:iva_cond]
      self.concepto   = attrs[:concepto]  || Bravo.default_concepto
    end

    def cbte_type
      Bravo::BILL_TYPE[iva_cond.to_sym] ||
        raise(NullOrInvalidAttribute.new, "Please choose a valid document type.")
    end

    def exchange_rate
      return 1 if moneda == :peso
      response = client.call :fe_param_get_cotizacion do
        message body.merge!({"MonId" => Bravo::MONEDAS[moneda][:codigo]})
      end
      response.to_hash[:fe_param_get_cotizacion_response][:fe_param_get_cotizacion_result][:result_get][:mon_cotiz].to_f
    end

    def total
      @total = net.zero? ? 0 : (net + iva_sum).round(2)
    end

    def iva_sum
      @iva_sum = net * Bravo::ALIC_IVA[aliciva_id][1]
      @iva_sum.round(2)
    end

    def authorize
      return false unless setup_bill

      response = client.call(:fecae_solicitar) do |soap|
        soap.message(body)
      end

      return false unless setup_response(response.to_hash)
      self.authorized?
    end

    def setup_bill
      today = Time.new.in_time_zone('Buenos Aires').strftime('%Y%m%d')

      fecaereq = {
        'FeCAEReq' => {
          'FeCabReq' => Bravo::Bill.header(cbte_type),
          'FeDetReq' => {
            'FECAEDetRequest' => {
              'Concepto'    => Bravo::CONCEPTOS[concepto],
              'DocTipo'     => Bravo::DOCUMENTOS[documento],
              'CbteFch'     => today,
              'ImpTotConc'  => 0.00,
              'MonId'       => Bravo::MONEDAS[moneda][:codigo],
              'MonCotiz'    => exchange_rate,
              'ImpOpEx'     => 0.00,
              'ImpTrib'     => 0.00,
              'Iva'         => {
                'AlicIva' => {
                  'Id' => '5',
                  'BaseImp' => net,
                  'Importe' => iva_sum
                }
              }
            }
          }
        }
      }

      self.recipient_iva_cond = parse_iva_cond(self.recipient_iva_cond) if self.recipient_iva_cond.is_a?(Symbol)
      if not self.recipient_iva_cond.is_a?(Integer)
        raise "La condición IVA del receptor es un campo requerido desde 04/2025"
      end

      detail = fecaereq['FeCAEReq']['FeDetReq']['FECAEDetRequest']

      detail['DocNro']    = self.doc_num
      detail["CondicionIVAReceptorId"] = self.recipient_iva_cond
      detail['ImpNeto']   = self.net.to_f
      detail['ImpIVA']    = self.iva_sum
      detail['ImpTotal']  = self.total

      if bill_number = next_bill_number
        detail['CbteDesde'] = detail['CbteHasta'] = bill_number
      else
        return false
      end

      unless concepto == 0
        detail.merge!({'FchServDesde' => fch_serv_desde || today,
                       'FchServHasta'  => fch_serv_hasta || today,
                       'FchVtoPago'    => due_date       || today})
      end


      body.merge!(fecaereq)
      true
    end

    def next_bill_number
      resp = client.call :fe_comp_ultimo_autorizado do |soap|
        soap.message(body.merge({"PtoVta" => Bravo.sale_point, "CbteTipo" => cbte_type}))
      end

      resp.to_hash[:fe_comp_ultimo_autorizado_response][:fe_comp_ultimo_autorizado_result][:cbte_nro].to_i + 1
    end

    def authorized?
      !response.nil? && response.header_result == "A" && response.detail_result == "A"
    end

    def query_bill(iva_condition, cbte_number)
      cbte_type_selected = Bravo::BILL_TYPE[iva_condition] ||
        raise(NullOrInvalidAttribute.new, 'Please choose a valid document type.')

      response = client.call :fe_comp_consultar do |soap|
        soap.message(body.merge({
          'FeCompConsReq' => {
            'PtoVta'    => Bravo.sale_point,
            'CbteTipo'  => cbte_type_selected,
            'CbteNro'   => cbte_number
          }
        }))
      end

      result = response.to_hash[:fe_comp_consultar_response][:fe_comp_consultar_result][:result_get]

      response_hash = {header_result: result[:resultado],
                       authorized_on: result[:fch_proceso],
                       detail_result: result[:resultado],
                       cae_due_date: result[:fch_vto],
                       cae: result[:cod_autorizacion],
                       iva_id: result[:iva][:alic_iva][:id],
                       iva_importe: result[:iva][:alic_iva][:importe],
                       moneda: result[:mon_id],
                       cotizacion: result[:mon_cotiz],
                       iva_base_imp: result[:iva][:alic_iva][:base_imp],
                       doc_num: result[:doc_nro]
      }

      self.response = Response.new(response_hash)
    end

    private

    class << self
      def header(cbte_type)#todo sacado de la factura
        {"CantReg" => "1", "CbteTipo" => cbte_type, "PtoVta" => Bravo.sale_point}
      end
    end

    def setup_response(response)
      begin
        result          = response[:fecae_solicitar_response][:fecae_solicitar_result]

        response_header = result[:fe_cab_resp]
        response_detail = result[:fe_det_resp][:fecae_det_response]

        request_header  = body["FeCAEReq"]["FeCabReq"].underscore_keys.symbolize_keys
        request_detail  = body["FeCAEReq"]["FeDetReq"]["FECAEDetRequest"].underscore_keys.symbolize_keys
      rescue NoMethodError
        if defined?(RAILS_DEFAULT_LOGGER) && logger = RAILS_DEFAULT_LOGGER
          logger.error "[BRAVO] NoMethodError: Response #{response}"
        else
          puts "[BRAVO] NoMethodError: Response #{response}"
        end
      return false
      end

      iva = request_detail.delete(:iva)["AlicIva"].underscore_keys.symbolize_keys

      request_detail.merge!(iva)

      response_hash = {
        header_result: response_header.delete(:resultado),
        authorized_on: response_header.delete(:fch_proceso),
        detail_result: response_detail.delete(:resultado),
        cae_due_date:  response_detail.delete(:cae_fch_vto),
        cae:           response_detail.delete(:cae),
        iva_id:        request_detail.delete(:id),
        iva_importe:   request_detail.delete(:importe),
        moneda:        request_detail.delete(:mon_id),
        cotizacion:    request_detail.delete(:mon_cotiz),
        iva_base_imp:  request_detail.delete(:base_imp),
        doc_num:       request_detail.delete(:doc_nro)
      }.merge!(request_header).merge!(request_detail)

      self.response = Response.new(response_hash)
    end

    def parse_iva_cond(sym)
      return 1 if sym == :responsable_inscripto
      return 6 if sym == :monotributo
      return 5 if sym == :consumidor_final
      return 4 if sym == :exento
    end
  end
end
