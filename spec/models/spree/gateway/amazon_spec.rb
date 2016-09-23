require 'spec_helper'

describe Spree::Gateway::Amazon do
  let(:payment_method) { Spree::Gateway::Amazon.for_currency(order.currency) }
  let!(:amazon_gateway) { create(:amazon_gateway) }
  let(:order) { create(:order_with_line_items, state: 'delivery') }
  let(:payment_source) { Spree::AmazonTransaction.create!(order_id: order.id, order_reference: 'REFERENCE') }
  let!(:payment) do
    create(:payment,
           order: order,
           payment_method: payment_method,
           source: payment_source,
           amount: order.total)
  end
  let(:mws) { payment_method.send(:load_amazon_mws, 'REFERENCE') }

  describe "#credit" do
    it 'succeeds' do
      allow_any_instance_of(Spree::Gateway::Amazon).to receive(:operation_unique_id).and_return('REFERENCE')
      amazon_transaction = create(:amazon_transaction, capture_id: "CAPTURE_ID")
      payment = create(:payment, source: amazon_transaction, amount: 30.0, payment_method: payment_method)
      refund = create(:refund, payment: payment, amount: 30.0)
      stub_refund_request(order: order)


      auth = payment_method.credit(order.total, nil, { originator: refund })
      expect(auth).to be_success
    end
  end

  describe '#authorize' do
    def stub_auth_request(expected_body: nil, return_values: nil)
      stub_request(
        :post,
        'https://mws.amazonservices.com/OffAmazonPayments_Sandbox/2013-01-01',
      ).with(
        body: expected_body || hash_including(
          'Action' => 'Authorize',
          'AmazonOrderReferenceId' => 'REFERENCE',
          'AuthorizationAmount.Amount' => '1.1',
          'AuthorizationAmount.CurrencyCode' => order.currency
        )
      ).to_return(
        return_values || {
          headers: {'content-type' => 'text/xml'},
          body: build_mws_auth_approved_response(order: order),
        },
      )
    end

    context 'when approved' do
      it 'succeeds' do
        stub_auth_request

        response = payment_method.authorize(order.total, payment_source, {order_id: payment.send(:gateway_order_id)})

        expect(response).to be_success
      end
    end

    context 'when declined' do
      it 'fails' do
        stub_auth_request(return_values: {
          headers: {'content-type' => 'text/xml'},
          status: 200,
          body: build_mws_auth_declined_response(order: order),
        })

        response = payment_method.authorize(order.total, payment_source, {order_id: payment.send(:gateway_order_id)})

        expect(response).not_to be_success
        expect(response.message).to eq('Authorization failure: InvalidPaymentMethod')
      end
    end

    context 'with an ErrorResponse error' do
      it 'fails' do
        stub_auth_request(return_values: {
          headers: {'content-type' => 'text/xml'},
          status: 400,
          body: build_mws_auth_error_response(order: order),
        })

        response = payment_method.authorize(order.total, payment_source, {order_id: payment.send(:gateway_order_id)})

        expect(response).not_to be_success
        expect(response.message).to match(/^400 TransactionAmountExceeded:/)
      end
    end

    context 'with a 5xx error' do
      it 'fails' do
        stub_auth_request(return_values: {
          headers: {'content-type' => 'text/plain'},
          status: 502,
          body: build_error_response(code: 502, message: "502 Bad Gateway")
        })

        response = payment_method.authorize(order.total, payment_source, {order_id: payment.send(:gateway_order_id)})

        expect(response).not_to be_success
        expect(response.message).to match(/502 Bad Gateway/)
      end
    end

    # 500 is special-cased in the Amazon library
    context 'with a 500 error' do
      it 'fails' do
        stub_auth_request(return_values: {
          headers: {'content-type' => 'text/plain'},
          status: 500,
          body: 'Server Error',
        })

        expect {
          response = payment_method.authorize(order.total, payment_source, {order_id: payment.send(:gateway_order_id)})
        }.to raise_error(Spree::Core::GatewayError, 'InternalServerError')
      end
    end

    # 503 is special-cased in the Amazon library
    context 'with a 503 error' do
      before do
        # Without this the specs have a big pause while the Amazon gem retries
        allow_any_instance_of(PayWithAmazon::Request).to receive(:get_seconds_for_try_count).and_return(0)
      end

      it 'fails' do
        stub_auth_request(return_values: {
          headers: {'content-type' => 'text/plain'},
          status: 503,
          body: 'Service Unavailable',
        })

        expect {
          response = payment_method.authorize(order.total, payment_source, {order_id: payment.send(:gateway_order_id)})
        }.to raise_error(Spree::Core::GatewayError, 'ServiceUnavailable or RequestThrottled')
      end
    end

    context 'with sandbox simulation strings' do
      context 'with a ship address' do
        let(:order) { create(:order_with_line_items, state: 'delivery', ship_address: ship_address) }
        let(:ship_address) do
          create(:address,
            firstname: 'InvalidPaymentMethodHard',
            lastname: 'SandboxSimulation',
          )
        end
        let(:expected_note) { '{"SandboxSimulation": {"State":"Declined", "ReasonCode":"InvalidPaymentMethod", "PaymentMethodUpdateTimeInMins":1}}' }

        it 'forwards the note to Amazon' do
          allow(mws).to receive(:authorize).and_call_original

          stub_auth_request(
            expected_body: hash_including(
              'Action' => 'Authorize',
              'SellerAuthorizationNote' => expected_note,
            ),
          )

          payment_method.authorize(order.total, payment_source, {order_id: payment.send(:gateway_order_id)})

          expect(mws).to have_received(:authorize).with(
            /^#{payment.number}-\w+$/,
            order.total/100,
            order.currency,
            seller_authorization_note: expected_note,
          )
        end
      end

      context 'without a ship address' do
        before do
          order.update_attributes!(ship_address: nil)
        end

        it 'does not forward a note to Amazon' do
          allow(mws).to receive(:authorize).and_call_original

          stub_auth_request

          payment_method.authorize(order.total, payment_source, {order_id: payment.send(:gateway_order_id)})

          expect(mws).to have_received(:authorize).with(
            /^#{payment.number}-\w+$/,
            order.total/100,
            order.currency,
            seller_authorization_note: nil,
          )
        end
      end
    end
  end

  describe '#capture' do
    def stub_capture_request(expected_body: nil, return_values: nil)
      stub_request(
        :post,
        'https://mws.amazonservices.com/OffAmazonPayments_Sandbox/2013-01-01',
      ).with(
        body: expected_body || hash_including(
          'Action' => 'Capture',
          'AmazonAuthorizationId' => 'AUTHORIZATION_ID',
          'CaptureReferenceId' => 'REFERENCE',
          'CaptureAmount.Amount' => '1.1',
          'CaptureAmount.CurrencyCode' => order.currency
        )
      ).to_return(
        return_values || {
          headers: {'content-type' => 'text/xml'},
          body: build_mws_capture_approved_response(order: order, capture_reference_id: 'REFERENCE'),
        },
      )
    end
    let(:payment_source) { create(:amazon_transaction, order_reference: 'REFERENCE', order_id: order.id) }
    it 'succeeds' do
      allow_any_instance_of(Spree::Gateway::Amazon).to receive(:operation_unique_id).and_return('REFERENCE')
      stub_capture_request


      auth = payment_method.capture(order.total, payment_source, {order_id: payment.send(:gateway_order_id)})

      expect(auth).to be_success
    end
  end

  describe '#purchase' do
    context 'when authorization fails' do
      let(:auth_result) { ActiveMerchant::Billing::Response.new(false, 'Error') }

      it 'returns the authorization result' do
        expect(payment_method).to receive(:authorize).and_return(auth_result)
        expect(payment_method).not_to receive(:capture)

        result = payment_method.purchase(order.total, payment_source, {order_id: payment.send(:gateway_order_id)})
        expect(result).to eq(auth_result)
      end
    end
  end

  context 'void' do
    describe 'payment has not yet been captured' do
      it 'cancel succeeds' do
        stub_cancel_request

        auth = payment_method.void('', {order_id: payment.send(:gateway_order_id)})
        expect(auth).to be_success
      end
    end
  end

  describe '.for_currency' do
    context 'when the currency exists and is active' do
      let!(:gbp_inactive_gateway) { create(:amazon_gateway, active: false, preferred_currency: 'GBP') }
      let!(:gbp_active_gateway) { create(:amazon_gateway, preferred_currency: 'GBP') }

      it 'finds the active gateway' do
        expect(Spree::Gateway::Amazon.for_currency('GBP')).to eq(gbp_active_gateway)
      end
    end

    context 'when the currency exists but is not active' do
      let!(:gbp_inactive_gateway) { create(:amazon_gateway, active: false, preferred_currency: 'GBP') }

      it 'returns nil' do
        expect(Spree::Gateway::Amazon.for_currency('GBP')).to eq(nil)
      end
    end

    context 'when the currency does not exist' do
      it 'returns nil' do
        expect(Spree::Gateway::Amazon.for_currency('ABC')).to eq(nil)
      end
    end
  end

  describe '#api_url' do
    let(:gbp_gateway) { create(:amazon_gateway, preferred_region: 'uk') }
    let(:usd_gateway) { create(:amazon_gateway, preferred_region: 'us') }
    it 'generates the url based on the region' do
      expect(gbp_gateway.api_url).not_to eq(usd_gateway.api_url)
    end
  end

  describe '#widgets_url' do
    let(:gbp_gateway) { create(:amazon_gateway, preferred_region: 'uk') }
    let(:usd_gateway) { create(:amazon_gateway, preferred_region: 'us') }
    it 'generates the url based on the region' do
      expect(gbp_gateway.widgets_url).not_to eq(usd_gateway.widgets_url)
    end
  end

  def stub_cancel_request
    stub_request(
      :post,
      'https://mws.amazonservices.com/OffAmazonPayments_Sandbox/2013-01-01',
    ).with(
      body: hash_including(
        'Action' => 'CancelOrderReference'
      )
    ).to_return(
      {
        headers: {'content-type' => 'text/xml'},
        body: build_mws_void_response
      },
    )
  end

  def stub_refund_request(order: nil)
    stub_request(
      :post,
      'https://mws.amazonservices.com/OffAmazonPayments_Sandbox/2013-01-01',
    ).with(
      body: hash_including(
        'Action' => 'Refund',
        'AmazonCaptureId' => 'CAPTURE_ID',
        'RefundReferenceId' => 'REFERENCE',
        'RefundAmount.Amount' => '1.1',
        'RefundAmount.CurrencyCode' => order.currency
      )
    ).to_return(
      {
        headers: {'content-type' => 'text/xml'},
        body: build_mws_refund_response(state: 'Pending', total: '1.1')
      },
    )
  end

  def build_mws_auth_approved_response(
    order:,
    authorization_reference_id: 'some-authorization-reference-id',
    amazon_authorization_id: 'some-amazon-authorization-id'
  )
    <<-XML.strip_heredoc
      <AuthorizeResponse xmlns="http://mws.amazonservices.com/schema/OffAmazonPayments/2013-01-01">
        <AuthorizeResult>
          <AuthorizationDetails>
            <AuthorizationAmount>
              <CurrencyCode>#{order.currency}</CurrencyCode>
              <Amount>#{order.total}</Amount>
            </AuthorizationAmount>
            <CapturedAmount>
              <CurrencyCode>#{order.currency}</CurrencyCode>
              <Amount>0</Amount>
            </CapturedAmount>
            <ExpirationTimestamp>2016-08-31T20:05:26.104Z</ExpirationTimestamp>
            <IdList/>
            <SoftDecline>false</SoftDecline>
            <AuthorizationStatus>
              <LastUpdateTimestamp>2016-08-01T20:05:26.104Z</LastUpdateTimestamp>
              <State>Open</State>
            </AuthorizationStatus>
            <AuthorizationFee>
              <CurrencyCode>#{order.currency}</CurrencyCode>
              <Amount>0.00</Amount>
            </AuthorizationFee>
            <AuthorizationBillingAddress>
              <Name>Jordan Brough</Name>
              <AddressLine1>1234 Way</AddressLine1>
              <City>Beverly Hills</City>
              <PostalCode>90210</PostalCode>
              <CountryCode>US</CountryCode>
            </AuthorizationBillingAddress>
            <CaptureNow>false</CaptureNow>
            <CreationTimestamp>2016-08-01T20:05:26.104Z</CreationTimestamp>
            <SellerAuthorizationNote/>
            <AmazonAuthorizationId>#{amazon_authorization_id}</AmazonAuthorizationId>
            <AuthorizationReferenceId>#{authorization_reference_id}</AuthorizationReferenceId>
          </AuthorizationDetails>
        </AuthorizeResult>
        <ResponseMetadata>
          <RequestId>2a7ec86e-ac87-45b4-aba9-245392e707c4</RequestId>
        </ResponseMetadata>
      </AuthorizeResponse>
    XML
  end

  def build_mws_auth_declined_response(
    order:,
    authorization_reference_id: 'some-authorization-reference-id',
    amazon_authorization_id: 'some-amazon-authorization-id'
  )
    <<-XML.strip_heredoc
      <AuthorizeResponse xmlns="http://mws.amazonservices.com/schema/OffAmazonPayments/2013-01-01">
        <AuthorizeResult>
          <AuthorizationDetails>
            <AuthorizationAmount>
              <CurrencyCode>#{order.currency}</CurrencyCode>
              <Amount>#{order.total}</Amount>
            </AuthorizationAmount>
            <CapturedAmount>
              <CurrencyCode>#{order.currency}</CurrencyCode>
              <Amount>0</Amount>
            </CapturedAmount>
            <ExpirationTimestamp>2016-08-31T20:03:42.608Z</ExpirationTimestamp>
            <SoftDecline>false</SoftDecline>
            <AuthorizationStatus>
              <LastUpdateTimestamp>2016-08-01T20:03:42.608Z</LastUpdateTimestamp>
              <State>Declined</State>
              <ReasonCode>InvalidPaymentMethod</ReasonCode>
            </AuthorizationStatus>
            <AuthorizationFee>
              <CurrencyCode>#{order.currency}</CurrencyCode>
              <Amount>0.00</Amount>
            </AuthorizationFee>
            <CaptureNow>false</CaptureNow>
            <CreationTimestamp>2016-08-01T20:03:42.608Z</CreationTimestamp>
            <SellerAuthorizationNote>{&quot;SandboxSimulation&quot;: {&quot;State&quot;:&quot;Declined&quot;, &quot;ReasonCode&quot;:&quot;InvalidPaymentMethod&quot;, &quot;PaymentMethodUpdateTimeInMins&quot;:1}}</SellerAuthorizationNote>
            <AmazonAuthorizationId>#{amazon_authorization_id}</AmazonAuthorizationId>
            <AuthorizationReferenceId>#{authorization_reference_id}</AuthorizationReferenceId>
          </AuthorizationDetails>
        </AuthorizeResult>
        <ResponseMetadata>
          <RequestId>b86614ce-2f63-4186-961e-e6548cdc509f</RequestId>
        </ResponseMetadata>
      </AuthorizeResponse>
    XML
  end

  def build_mws_auth_error_response(order:)
    <<-XML.strip_heredoc
      <ErrorResponse xmlns="http://mws.amazonservices.com/schema/OffAmazonPayments/2013-01-01">
        <Error>
          <Type>Sender</Type>
          <Code>TransactionAmountExceeded</Code>
          <Message>An Authorization request with amount 1000.00 USD cannot be accepted. The total Authorization amount against the OrderReference some-order-reference-id cannot exceed #{order.total} #{order.currency}.</Message>
        </Error>
        <RequestId>afca042f-0f64-ba8c-89b1-9be261bc7381</RequestId>
      </ErrorResponse>
    XML
  end

  def build_mws_capture_approved_response(
    order:,
    capture_reference_id: 'some-capture-reference-id',
    amazon_capture_id: 'some-amazon-capture-id'
  )
    <<-XML.strip_heredoc
      <CaptureResponse xmlns="https://mws.amazonservices.com/schema/OffAmazonPayments/2013-01-01">
        <CaptureResult>
          <CaptureDetails>
            <AmazonCaptureId>#{amazon_capture_id}</AmazonCaptureId>
            <CaptureReferenceId>#{capture_reference_id}</CaptureReferenceId>
            <SellerCaptureNote>Lorem ipsum</SellerCaptureNote>
            <CaptureAmount>
              <CurrencyCode>#{order.currency}</CurrencyCode>
              <Amount>#{order.total}</Amount>
            </CaptureAmount>
            <CaptureStatus>
              <State>Completed</State>
              <LastUpdateTimestamp>2012-11-03T19:10:16Z</LastUpdateTimestamp>
            </CaptureStatus>
            <CreationTimestamp>2012-11-03T19:10:16Z</CreationTimestamp>
          </CaptureDetails>
        </CaptureResult>
        <ResponseMetadata>
          <RequestId>b4ab4bc3-c9ea-44f0-9a3d-67cccef565c6</RequestId>
        </ResponseMetadata>
      </CaptureResponse>
    XML
  end

  def build_mws_capture_response(
    order:,
    capture_reference_id: 'some-capture-reference-id',
    amazon_capture_id: 'some-amazon-capture-id'
  )
    {
      "CaptureResponse" => {
        "CaptureResult" => {
          "CaptureDetails" => {
            "AmazonCaptureId" => amazon_capture_id,
            "CaptureReferenceId" => capture_reference_id,
            "SellerCaptureNote" => "Lorem ipsum",
            "CaptureAmount" => {
              "CurrencyCode" => "USD",
              "Amount" => order.total
            },
            "CaptureStatus" => {
              "State" => "Open",
              "LastUpdateTimestamp" => "2012-11-03T19:10:16Z"
            },
            "CreationTimestamp" => "2012-11-03T19:10:16Z"
          }
        },
        "ResponseMetadata" => { "RequestId" => "b4ab4bc3-c9ea-44f0-9a3d-67cccef565c6" }
      }
    }
  end

  def build_mws_refund_response(state:, total:)
    <<-XML.strip_heredoc
      <RefundResponse xmlns="https://mws.amazonservices.com/schema/OffAmazonPayments/2013-01-01">
        <RefundResult>
          <RefundDetails>
            <AmazonRefundId>P01-1234567-1234567-0000003</AmazonRefundId>
            <RefundReferenceId>test_refund_1</RefundReferenceId>
            <SellerRefundNote></SellerRefundNote>
            <RefundType>SellerInitiated</RefundType>
            <RefundedAmount>
              <CurrencyCode>USD</CurrencyCode>
              <Amount>#{total}</Amount>
            </RefundedAmount>
            <FeeRefunded>
              <CurrencyCode>USD</CurrencyCode>
              <Amount>0</Amount>
            </FeeRefunded>
            <RefundStatus>
              <State>#{state}</State>
              <LastUpdateTimestamp>2012-11-07T19:10:16Z</LastUpdateTimestamp>
            </RefundStatus>
            <CreationTimestamp>2012-11-05T19:10:16Z</CreationTimestamp>
          </RefundDetails>
        </RefundResult>
        <ResponseMetadata>
          <RequestId>b4ab4bc3-c9ea-44f0-9a3d-67cccef565c6</RequestId>
        </ResponseMetadata>
      </RefundResponse>
    XML
  end

  def build_mws_void_response
    <<-XML.strip_heredoc
        <CancelOrderReferenceResponse
  xmlns="https://mws.amazonservices.com/schema/OffAmazonPayments/2013-01-01">
        <ResponseMetadata>
          <RequestId>5f20169b-7ab2-11df-bcef-d35615e2b044</RequestId>
        </ResponseMetadata>
      </CancelOrderReferenceResponse>
    XML
  end

  def build_error_response(code: 400, message: 'FAILURE')
    <<-XML.strip_heredoc
      <ErrorResponse xmlns="http://mws.amazonservices.com/schema/OffAmazonPayments/2013-01-01">
        <Error>
          <Type>Sender</Type>
          <Code>#{code}</Code>
          <Message>#{message}</Message>
        </Error>
        <RequestId>7a1a4219-7b80-4d32-a08c-708fd7f52ebc</RequestId>
      </ErrorResponse>
    XML
  end
end
