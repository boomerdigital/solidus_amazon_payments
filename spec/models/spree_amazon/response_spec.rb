require 'spec_helper'

describe SpreeAmazon::Response, type: :model do

  context 'Capture' do
    let(:capture_state) { 'Completed' }
    let(:mws_capture_response) { build_mws_capture_response(state: capture_state, total: 100.00) }
    let(:response) { SpreeAmazon::Response.new('Capture', mws_capture_response) }

    describe '#result' do
      it 'returns CaptureResult hash' do
        expect(response.result).to eq(mws_capture_response['CaptureResponse']['CaptureResult'])
      end
    end

    describe '#details' do
      it 'returns CaptureDetails hash' do
        expect(response.details).to eq(mws_capture_response['CaptureResponse']['CaptureResult']['CaptureDetails'])
      end
    end

    describe '#capture_id' do
      it 'returns AmazonCaptureId' do
        mws_capture_response['CaptureResponse']['CaptureResult']['CaptureDetails']['AmazonCaptureId'] = '123456789'

        expect(response.capture_id).to eq('123456789')
      end
    end

    describe '#reference_id' do
      it 'returns ReferenceCaptureId' do
        mws_capture_response['CaptureResponse']['CaptureResult']['CaptureDetails']['ReferenceCaptureId'] = '123456789'

        expect(response.reference_id).to eq('123456789')
      end
    end

    describe '#amount' do
      it 'returns 100.00' do
        expect(response.amount).to eq(100.00)
      end
    end

    describe '#currency_code' do
      it 'returns USD' do
        mws_capture_response['CaptureResponse']['CaptureResult']['CaptureDetails']['CaptureAmount']['CurrencyCode'] = 'USD'

        expect(response.currency_code).to eq('USD')
      end
    end

    describe '#status' do
      it 'returns Completed' do
        expect(response.status).to eq('Completed')
      end
    end

    describe '#success?' do
      context 'success' do
        let(:capture_state) { 'Completed' }

        it 'returns true' do
          expect(response.success?).to be_truthy
        end
      end

      context 'fail' do
        let(:capture_state) { 'Fail' }
        it 'returns false' do
          expect(response.success?).to be_falsey
        end
      end
    end
  end

  def build_mws_capture_response(state:, total:)
    {
      "CaptureResponse" => {
        "CaptureResult" => {
          "CaptureDetails" => {
            "AmazonCaptureId" => "P01-1234567-1234567-0000002",
            "CaptureReferenceId" => "test_capture_1",
            "SellerCaptureNote" => "Lorem ipsum",
            "CaptureAmount" => {
              "CurrencyCode" => "USD",
              "Amount" => total
            },
            "CaptureStatus" => {
              "State" => state,
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
    {
      "RefundResponse" => {
        "RefundResult" => {
          "RefundDetails" => {
            "AmazonRefundId" => "P01-1234567-1234567-0000003",
            "RefundReferenceId" => "test_refund_1",
            "SellerRefundNote" => "Lorem ipsum",
            "RefundType" => "SellerInitiated",
            "RefundedAmount" => {
              "CurrencyCode" => "USD",
              "Amount" => total
            },
            "FeeRefunded" => {
              "CurrencyCode" => "USD",
              "Amount" => "0"
            },
            "RefundStatus" => {
              "State" => state,
              "LastUpdateTimestamp" => "2012-11-07T19:10:16Z"
            },
            "CreationTimestamp" => "2012-11-05T19:10:16Z"
          }
        },
        "ResponseMetadata" => { "RequestId" => "b4ab4bc3-c9ea-44f0-9a3d-67cccef565c6" }
      }
    }
  end

  def build_mws_void_response
    {
      "CancelOrderReferenceResponse" => {
        "CancelOrderReferenceResult"=> nil,
        "ResponseMetadata" => { "RequestId" => "b4ab4bc3-c9ea-44f0-9a3d-67cccef565c6" }
      }
    }
  end
end
