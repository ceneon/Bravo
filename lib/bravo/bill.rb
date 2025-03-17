module Bravo
  class Bill
    attr_reader :client, :base_imp, :total
    attr_accessor :net, :doc_num, :iva_cond, :recipient_iva_cond,
                  :documento, :concepto, :moneda,
                  :due_date, :fch_serv_desde, :fch_serv_hasta, :fch_emision,
                  :body, :response, :ivas, :related_invoice_data

    def initialize(attrs = {})
      Bravo::AuthData.fetch
      @client         = Savon::Client.new do
        wsdl.document = Bravo.service_url
        http.auth.ssl.cert_key_file = Bravo.pkey
        http.auth.ssl.cert_file = Bravo.cert
        http.auth.ssl.verify_mode = :none
        http.read_timeout = 90
        http.open_timeout = 90
        http.headers = { "Accept-Encoding" => "gzip, deflate", "Connection" => "Keep-Alive" }

        # Insist because this config doesn't stick from bravo.rb for some reason
        config.logger = Rails.logger
        config.log = true
        config.log_level = :debug
      end

      @body           = {"Auth" => Bravo.auth_hash}
      @net            = attrs[:net] || 0
      self.documento  = attrs[:documento] || Bravo.default_documento
      self.moneda     = attrs[:moneda]    || Bravo.default_moneda
      self.iva_cond   = attrs[:iva_cond]
      self.concepto   = attrs[:concepto]  || Bravo.default_concepto
      self.ivas = attrs[:ivas] || Array.new # [ 1, 100.00, 10.50 ], [ 2, 100.00, 21.00 ] 
    end

    def cbte_type
      Bravo::BILL_TYPE[Bravo.own_iva_cond][iva_cond] ||
        raise(NullOrInvalidAttribute.new, "Please choose a valid document type.")
    end

    def exchange_rate
      return 1 if moneda == :peso
      response = client.request :fe_param_get_cotizacion do
        soap.namespaces["xmlns"] = "http://ar.gov.afip.dif.FEV1/"
        soap.body = body.merge!({"MonId" => Bravo::MONEDAS[moneda][:codigo]})
      end
      response.to_hash[:fe_param_get_cotizacion_response][:fe_param_get_cotizacion_result][:result_get][:mon_cotiz].to_f
    end

    def total
      @total = net.zero? ? 0 : net + iva_sum
    end

    def iva_sum
      @iva_sum = 0.0
      self.ivas.each{ |i|
        @iva_sum += i[1] * Bravo::ALIC_IVA[ i[0] ][1]
        # @iva_sum += i[2] 
      }
      #@iva_sum = net * Bravo::ALIC_IVA[TODO][1]
      #@iva_sum.round_up_with_precision(2)
      @iva_sum.round(2)
    end

    def authorize
      setup_bill
      response = client.request :fecae_solicitar do |soap|
        soap.namespaces["xmlns"] = "http://ar.gov.afip.dif.FEV1/"
        soap.body = body
      end

      setup_response(response.to_hash)
      self.authorized?
    end

    def setup_bill
      if fch_emision then
        fecha_emision = fch_emision.strftime('%Y%m%d')
      else
        fecha_emision = Time.new.strftime('%Y%m%d') #today
      end
       

      array_ivas = Array.new
      self.ivas.each{ |i|
          array_ivas << {
              "Id" => Bravo::ALIC_IVA[ i[0] ][0],
              "BaseImp" => i[1] ,
              "Importe" => i[2] }
      }

      fecaereq = {"FeCAEReq" => {
                    "FeCabReq" => Bravo::Bill.header(cbte_type),
                    "FeDetReq" => {
                      "FECAEDetRequest" => {
                        "Concepto"    => Bravo::CONCEPTOS[concepto],
                        "DocTipo"     => Bravo::DOCUMENTOS[documento],
                        "CbteFch"     => fecha_emision,
                        "ImpTotConc"  => 0.00,
                        "MonId"       => Bravo::MONEDAS[moneda][:codigo],
                        "MonCotiz"    => exchange_rate,
                        "ImpOpEx"     => 0.00,
                        "ImpTrib"     => 0.00
                    }}}}

      if Bravo.own_iva_cond == :responsable_inscripto
        fecaereq["FeCAEReq"]["FeDetReq"]["FECAEDetRequest"]["Iva"] = { "AlicIva" => array_ivas }
      elsif Bravo.own_iva_cond == :responsable_monotributo and array_ivas.any?
        raise "No incluir montos iva al facturar como Responsable Monotributo"
      end

      self.recipient_iva_cond = parse_iva_cond(self.recipient_iva_cond) if self.recipient_iva_cond.is_a?(Symbol)
      if not self.recipient_iva_cond.is_a?(Integer)
        raise "La condición IVA del receptor es un campo requerido desde 04/2025"
      end

      detail = fecaereq["FeCAEReq"]["FeDetReq"]["FECAEDetRequest"]

      detail["DocNro"]    = doc_num
      detail["CondicionIVAReceptorId"] = self.recipient_iva_cond
      detail["ImpNeto"]   = net.to_f
      detail["ImpIVA"]    = iva_sum
      detail["ImpTotal"]  = total.round(2)
      detail["CbteDesde"] = detail["CbteHasta"] = next_bill_number

      if related_invoice_data
        detail["CbtesAsoc"] = {
          "CbteAsoc" => [{
            "Tipo" => related_invoice_data[:type],
            "PtoVta" => related_invoice_data[:sale_point],
            "Nro" => related_invoice_data[:number],
            "Cuit" => related_invoice_data[:cuit],
            "CbteFch" => related_invoice_data[:date]
          }]
        }
      elsif ["02", "03", "07", "08"].include?(cbte_type) # NC/ND only
        detail["PeriodoAsoc"] = {
          "FchDesde" => fch_emision.beginning_of_month.strftime('%Y%m%d'),
          "FchHasta" => fch_emision.strftime('%Y%m%d')
        }
      end

      unless concepto == "Productos" # En "Productos" ("01"), si se mandan estos parámetros la afip rechaza.
        detail.merge!({"FchServDesde" => fch_serv_desde || today,
                      "FchServHasta"  => fch_serv_hasta || today,
                      "FchVtoPago"    => due_date       || today})
      end

      body.merge!(fecaereq)
    end

    def next_bill_number
      resp = client.request :fe_comp_ultimo_autorizado do
        soap.namespaces["xmlns"] = "http://ar.gov.afip.dif.FEV1/"
        soap.body = {"Auth" => Bravo.auth_hash, "PtoVta" => Bravo.sale_point, "CbteTipo" => cbte_type}
      end

      resp.to_hash[:fe_comp_ultimo_autorizado_response][:fe_comp_ultimo_autorizado_result][:cbte_nro].to_i + 1
    end

    def authorized?       
        !response.nil? && response.header_result == "A" && response.detail_result == "A"
    end

    def search(cbte_type, cbte_nro, pto_vta)
      fecompconsultarreq = {
        "FeCompConsReq" => {
          "CbteTipo" => cbte_type,
          "CbteNro" => cbte_nro,
          "PtoVta" => pto_vta
        }
      }
      body.merge!(fecompconsultarreq)

      response = client.request("FECompConsultar", soap_action: "http://ar.gov.afip.dif.FEV1/FECompConsultar") do |soap|
        soap.namespaces["xmlns"] = "http://ar.gov.afip.dif.FEV1/"
        soap.body = body
      end
      puts "FECompConsultar --> "
      puts body
      return response.to_json
    end

    private

    class << self
      def header(cbte_type)#todo sacado de la factura
        {"CantReg" => "1", "CbteTipo" => cbte_type, "PtoVta" => Bravo.sale_point}
      end
    end

    def setup_response(response)
      # TODO: turn this into an all-purpose Response class

      result          = response[:fecae_solicitar_response][:fecae_solicitar_result]
          
      if not result[:fe_det_resp] or not result[:fe_cab_resp] then 
      # Si no obtuvo respuesta ni cabecera ni detalle, evito hacer '[]' sobre algo indefinido.                        
      # Ejemplo: Error con el token-sign de WSAA
          keys, values = {
                :errores => result[:errors],
                :header_result => {:resultado => "X" },
                :observaciones => nil
          }.to_a.transpose
          self.response = (defined?(Struct::ResponseMal) ? Struct::ResponseMal : Struct.new("ResponseMal", *keys)).new(*values)         
          return
      end       
      
      response_header = result[:fe_cab_resp]
      response_detail = result[:fe_det_resp][:fecae_det_response]

      request_header  = body["FeCAEReq"]["FeCabReq"].underscore_keys.symbolize_keys
      request_detail  = body["FeCAEReq"]["FeDetReq"]["FECAEDetRequest"].underscore_keys.symbolize_keys
      
      # Esto no funciona desde que se soportan múltiples alícuotas de iva simultáneas
      # FIX ? TO-DO
      # iva             = request_detail.delete(:iva)["AlicIva"].underscore_keys.symbolize_keys
      # request_detail.merge!(iva) 
         
      if result[:errors] then
          response_detail.merge!( result[:errors] )     
      end
      
      response_hash = {:header_result => response_header.delete(:resultado),
                       :authorized_on => response_header.delete(:fch_proceso),
                       :detail_result => response_detail.delete(:resultado),
                       :cae_due_date  => response_detail.delete(:cae_fch_vto),
                       :cae           => response_detail.delete(:cae),
                       :iva_id        => request_detail.delete(:id),
                       :iva_importe   => request_detail.delete(:importe),
                       :moneda        => request_detail.delete(:mon_id),
                       :cotizacion    => request_detail.delete(:mon_cotiz),
                       :iva_base_imp  => request_detail.delete(:base_imp),
                       :doc_num       => request_detail.delete(:doc_nro), 
                       :observaciones => response_detail.delete(:observaciones),
                       :errores       => response_detail.delete(:err) 
                       }.merge!(request_header).merge!(request_detail)

      keys, values  = response_hash.to_a.transpose
      
      #self.response = (defined?(Struct::Response) ? Struct::Response : Struct.new("Response", *keys)).new(*values)
      # Even if it throws a warning, it avoids some parsing errors.
      self.response = Struct.new("Response", *keys).new(*values)
    end

    def parse_iva_cond(sym)
      return 1 if sym == :responsable_inscripto
      return 6 if sym == :monotributo
      return 5 if sym == :consumidor_final
      return 4 if sym == :exento
    end
  end
end
