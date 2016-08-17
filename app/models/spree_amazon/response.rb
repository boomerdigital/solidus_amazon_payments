class SpreeAmazon::Response
  attr_reader :authorization, :type, :mws_response

  def initialize(type, mws_response)
    @type = type.capitalize
    @mws_response = mws_response
    @authorization = nil
  end

  def result
    if type == 'Authorization'
      mws_response.fetch("AuthorizeResponse", {}).fetch("AuthorizeResult", {})
    else
      mws_response.fetch("#{@type}Response", {}).fetch("#{@type}Result", {})
    end
  end

  def details
    result.fetch("#{@type}Details", {})
  end

  def response_id
    details.fetch("Amazon#{@type}Id", nil)
  end
  alias_method :capture_id, :response_id
  alias_method :authorization_id, :response_id

  def reference_id
    details.fetch("Reference#{@type}Id", nil)
  end

  def amount
    details.fetch("#{@type}Amount", {}).fetch("Amount", nil)
  end

  def currency_code
    details.fetch("#{@type}Amount", {}).fetch("CurrencyCode", nil)
  end

  def status
    details.fetch("#{@type}Status", {}).fetch("State", nil)
  end

  def success?
    case @type
    when 'Capture'
      status == 'Completed'
    when 'Authorization'
      status == 'Open'
    else
      false
    end
  end

  def error_message
    if !success?
    end
  end
end
