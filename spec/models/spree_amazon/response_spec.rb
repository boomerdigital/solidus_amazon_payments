require 'spec_helper'

describe SpreeAmazon::Response do
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
  let(:payment_source) { create(:amazon_transaction, order_reference: 'REFERENCE', order_id: order.id) }

  context 'SpreeAmazon::Response::Capture' do
    describe '#initialize' do
      it 'sets @type' do
        capture_response = SpreeAmazon::Response::Capture.new('response')

        expect(capture_response.type).to eq('Capture')
      end

      it 'sets @response' do
        capture_response = SpreeAmazon::Response::Capture.new('response')

        expect(capture_response.response).to eq('response')
      end
    end

    describe '#response_details' do
      it 'returns path to response details' do
        capture_response = SpreeAmazon::Response::Capture.new('response')

        expect(capture_response.response_details).to eq('CaptureResponse/CaptureResult/CaptureDetails')
      end
    end

    context 'with real response' do
      before do
        load_mws(order, amazon_gateway)
      end


      let(:success_response) { @mws.capture('AUTHORIZATION_ID', 'REFERENCE', order.total.to_f, 'USD') }
      let(:fail_response) { @mws.capture('AUTHORIZATION_ID', 'REFERENCE', order.total.to_f, 'USD', seller_capture_note: "failfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfailfail") }

      let(:stub_capture_success) {
        stub_capture_request(
          order: order,
          ref_id: 'REFERENCE',
          auth_id: 'AUTHORIZATION_ID',
          capture_id: 'CAPTURE_ID',
          status: 200,
          body: build_mws_capture_approved_response(order: order, capture_reference_id: 'REFERENCE', amazon_capture_id: 'CAPTURE_ID')
        )
      }

      let(:stub_capture_error) {
        stub_capture_request(
          order: order,
          ref_id: 'REFERENCE',
          auth_id: 'AUTHORIZATION_ID',
          capture_id: 'CAPTURE_ID',
          status: 400,
          body: build_error_response
        )
      }



      describe '#response_id' do
        it 'returns AmazonCaptureId' do
          stub_capture_success
          capture_response = SpreeAmazon::Response::Capture.new(success_response)

          expect(capture_response.response_id).to eq('CAPTURE_ID')
        end

        it 'fetches' do
          stub_capture_success
          capture_response = SpreeAmazon::Response::Capture.new(success_response)

          expect(capture_response).to receive(:fetch)

          capture_response.response_id
        end
      end

      describe '#reference_id' do
        it 'returns AmazonReferenceId' do
          stub_capture_success
          capture_response = SpreeAmazon::Response::Capture.new(success_response)

          expect(capture_response.reference_id).to eq('REFERENCE')
        end

        it 'fetches' do
          stub_capture_success
          capture_response = SpreeAmazon::Response::Capture.new(success_response)

          expect(capture_response).to receive(:fetch)

          capture_response.reference_id
        end
      end

      describe '#amount' do
        it 'returns Amount equal to order total' do
          stub_capture_success
          capture_response = SpreeAmazon::Response::Capture.new(success_response)

          expect(capture_response.amount).to eq('110.0')
        end

        it 'fetches' do
          stub_capture_success
          capture_response = SpreeAmazon::Response::Capture.new(success_response)

          expect(capture_response).to receive(:fetch)

          capture_response.amount
        end
      end

      describe '#currency_code' do
        it 'returns CurrencyCode equal to USD' do
          stub_capture_success
          capture_response = SpreeAmazon::Response::Capture.new(success_response)

          expect(capture_response.currency_code).to eq('USD')
        end

        it 'fetches' do
          stub_capture_success
          capture_response = SpreeAmazon::Response::Capture.new(success_response)

          expect(capture_response).to receive(:fetch)

          capture_response.currency_code
        end
      end


      describe '#state' do
        it 'returns State' do
          stub_capture_success
          capture_response = SpreeAmazon::Response::Capture.new(success_response)

          expect(capture_response.state).to eq('Completed')
        end

        it 'fetches' do
          stub_capture_success
          capture_response = SpreeAmazon::Response::Capture.new(success_response)

          expect(capture_response).to receive(:fetch)

          capture_response.state
        end
      end

      describe '#success_state?' do
        it 'returns true' do
          stub_capture_success
          capture_response = SpreeAmazon::Response::Capture.new(success_response)

          expect(capture_response.success_state?).to be_truthy
        end
      end

      describe '#success?' do
        it 'returns true' do
          stub_capture_success
          capture_response = SpreeAmazon::Response::Capture.new(success_response)

          expect(capture_response.success?).to be_truthy
        end
      end

      describe '#response_code' do
        context 'success' do
          it 'returns 200' do
            stub_capture_success
            capture_response = SpreeAmazon::Response::Capture.new(success_response)

            expect(capture_response.response_code).to eq("200")
          end
        end

        context 'error' do
          it 'returns 400 code' do
            stub_capture_error
            capture_response = SpreeAmazon::Response::Capture.new(fail_response)

            capture_response.response_code

            expect(capture_response.response_code).to eq("400")
          end
        end
      end

      describe '#error_code' do
        context 'success' do
          it 'returns nil' do
            stub_capture_success
            capture_response = SpreeAmazon::Response::Capture.new(success_response)

            expect(capture_response.error_code).to be_nil
          end
        end

        context 'error' do
          it 'returns 400' do
            stub_capture_error
            capture_response = SpreeAmazon::Response::Capture.new(fail_response)

            expect(capture_response.error_code).to eq("400")
          end


          it 'fetches' do
            stub_capture_error
            capture_response = SpreeAmazon::Response::Capture.new(fail_response)

            expect(capture_response).to receive(:fetch)

            capture_response.error_code
          end
        end
      end

      describe '#error_message' do
        context 'success' do
          it 'returns nil' do
            stub_capture_success
            capture_response = SpreeAmazon::Response::Capture.new(success_response)

            expect(capture_response.error_message).to be_nil
          end
        end

        context 'error' do
          it 'returns 400' do
            stub_capture_error
            capture_response = SpreeAmazon::Response::Capture.new(fail_response)

            expect(capture_response.error_message).to eq("FAILURE")
          end

          it 'fetches' do
            stub_capture_error
            capture_response = SpreeAmazon::Response::Capture.new(fail_response)

            expect(capture_response).to receive(:fetch)

            capture_response.error_message
          end
        end
      end

      describe '#error_response_present?' do
        context 'success' do
          it 'returns false' do
            stub_capture_success
            capture_response = SpreeAmazon::Response::Capture.new(success_response)

            expect(capture_response.error_response_present?).to be_falsey
          end
        end

        context 'fail' do
          it 'returns true' do
            stub_capture_error
            capture_response = SpreeAmazon::Response::Capture.new(fail_response)

            expect(capture_response.error_response_present?).to be_truthy
          end
        end
      end

      describe '#body' do
        it 'returns xml body' do
          stub_capture_success
          capture_response = SpreeAmazon::Response::Capture.new(success_response)

          expect(capture_response.body).to eq(success_response.body)
        end
      end

      describe '#parse' do
        it 'returns a hash' do
          stub_capture_success
          capture_response = SpreeAmazon::Response::Capture.new(success_response)

          expect(capture_response.parse).to be_kind_of(Hash)
        end
      end
    end
  end

  context 'SpreeAmazon::Response::Authorization' do
    describe '#initialize' do
      it 'sets @type' do
        auth_response = SpreeAmazon::Response::Authorization.new('response')

        expect(auth_response.type).to eq('Authorization')
      end

      it 'sets @response' do
        auth_response = SpreeAmazon::Response::Authorization.new('response')

        expect(auth_response.response).to eq('response')
      end
    end

    describe '#response_details' do
      it 'returns path to response details' do
        auth_response = SpreeAmazon::Response::Authorization.new('response')

        expect(auth_response.response_details).to eq('AuthorizeResponse/AuthorizeResult/AuthorizationDetails')
      end
    end

    context 'with real response' do
      before do
        load_mws(order, amazon_gateway)
      end

      let(:response) { @mws.authorize('AUTH_REF', order.total.to_f, 'USD') }

      let(:stub_auth_success) {
        stub_auth_request(
          order: order,
          auth_ref: 'AUTH_REF',
          status: 200,
          body: get_authorization_response(order: order, auth_ref: 'AUTH_REF')
        )
      }

      let(:stub_auth_declined) {
        stub_auth_request(
          order: order,
          auth_ref: 'AUTH_REF',
          status: 200,
          body: build_mws_auth_declined_response(order: order, auth_ref: 'AUTH_REF')
        )
      }


      describe '#reason_code' do
        context 'successful auth' do
          it 'returns nil' do
            stub_auth_success
            auth_response = SpreeAmazon::Response::Authorization.new(response)

            expect(auth_response.reason_code).to be_nil
          end
        end

        context 'declined' do
          it 'returns InvalidPaymentMethod' do
            stub_auth_declined
            auth_response = SpreeAmazon::Response::Authorization.new(response)

            expect(auth_response.reason_code).to eq('InvalidPaymentMethod')
          end
        end
      end
    end
  end

  def load_mws(order, gateway)
    @mws ||= AmazonMws.new(order.amazon_order_reference_id, gateway: gateway)
  end

  def stub_capture_request(order:, auth_id:, ref_id:, capture_id:, body:, status:)
    stub_request(
      :post,
      'https://mws.amazonservices.com/OffAmazonPayments_Sandbox/2013-01-01',
    ).with(
      body: hash_including(
        'Action' => 'Capture',
        'AmazonAuthorizationId' => auth_id,
        'CaptureReferenceId' => ref_id,
        'CaptureAmount.Amount' => order.total.to_s,
        'CaptureAmount.CurrencyCode' => 'USD'
      )
    ).to_return(
      {
        headers: {'content-type' => 'text/xml'},
        body: body,
        status: status
      },
    )
  end

  def stub_auth_request(order:, auth_ref:, body:, status:)
    stub_request(
      :post,
      'https://mws.amazonservices.com/OffAmazonPayments_Sandbox/2013-01-01',
    ).with(
      body: hash_including(
        'Action' => 'Authorize',
        'AmazonOrderReferenceId' => order.amazon_order_reference_id,
        'AuthorizationAmount.Amount' => order.total.to_s,
        'AuthorizationAmount.CurrencyCode' => 'USD'
      )
    ).to_return(
      {
        headers: {'content-type' => 'text/xml'},
        body: body,
        status: status
      },
    )
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
              <Amount>#{order.total.to_f}</Amount>
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

  def get_authorization_response(order:, auth_ref:)
    <<-XML.strip_heredoc
      <AuthorizeResponse xmlns=" https://mws.amazonservices.com/schema/
  OffAmazonPayments/2013-01-01">
        <AuthorizeResult>
          <AuthorizationDetails>
            <AmazonAuthorizationId>
              P01-1234567-1234567-0000001
            </AmazonAuthorizationId>
          <AuthorizationReferenceId>#{auth_ref}</AuthorizationReferenceId>
            <SellerAuthorizationNote></SellerAuthorizationNote>
            <AuthorizationAmount>
              <CurrencyCode>#{order.currency}</CurrencyCode>
              <Amount>#{order.total.to_f}</Amount>
            </AuthorizationAmount>
            <AuthorizationFee>
              <CurrencyCode>#{order.currency}</CurrencyCode>
              <Amount>0</Amount>
            </AuthorizationFee>
        <SoftDecline>true</SoftDecline>
            <AuthorizationStatus>
              <State>Pending</State>
              <LastUpdateTimestamp>2012-11-03T19:10:16Z</LastUpdateTimestamp>
            </AuthorizationStatus>
            <CreationTimestamp>2012-11-02T19:10:16Z</CreationTimestamp>
            <ExpirationTimestamp>2012-12-02T19:10:16Z</ExpirationTimestamp>
          </AuthorizationDetails>
        </AuthorizeResult>
        <ResponseMetadata>
          <RequestId>b4ab4bc3-c9ea-44f0-9a3d-67cccef565c6</RequestId>
        </ResponseMetadata>
      </AuthorizeResponse>
    XML
  end

  def build_mws_auth_declined_response(
    order:,
    auth_ref: 'some-authorization-reference-id',
    amazon_authorization_id: 'some-amazon-authorization-id'
  )
    <<-XML.strip_heredoc
      <AuthorizeResponse xmlns="http://mws.amazonservices.com/schema/OffAmazonPayments/2013-01-01">
        <AuthorizeResult>
          <AuthorizationDetails>
            <AuthorizationAmount>
              <CurrencyCode>#{order.currency}</CurrencyCode>
              <Amount>#{order.total.to_f}</Amount>
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
            <AmazonAuthorizationId>P01-1234567-1234567-0000001</AmazonAuthorizationId>
            <AuthorizationReferenceId>#{auth_ref}</AuthorizationReferenceId>
          </AuthorizationDetails>
        </AuthorizeResult>
        <ResponseMetadata>
          <RequestId>b86614ce-2f63-4186-961e-e6548cdc509f</RequestId>
        </ResponseMetadata>
      </AuthorizeResponse>
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
