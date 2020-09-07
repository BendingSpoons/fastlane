require_relative '../model'
module Spaceship
  class ConnectAPI
    class InAppPurchaseReviewSubmission
      include Spaceship::ConnectAPI::Model

      attr_accessor :submission_type

      attr_mapping({
                       "submissionType" => "submission_type"
                   })

      def self.type
        return "inAppPurchaseReviewSubmissions"
      end

      #
      # API
      #

      def self.create(in_app_purchase_id: nil)
        Spaceship::ConnectAPI.post_in_app_purchase_review_submission(in_app_purchase_id: in_app_purchase_id).first
      end

      def self.get(in_app_purchase_review_submission_id: nil)
        Spaceship::ConnectAPI.get_in_app_purchase_review_submission(in_app_purchase_review_submission_id: in_app_purchase_review_submission_id).first
      end

      def delete!
        Spaceship::ConnectAPI.delete_in_app_purchase_review_submission(in_app_purchase_review_submission_id: id)
      end
    end
  end
end
