require 'spaceship/connect_api/private/testflight/client'

module Spaceship
  class ConnectAPI
    module TestFlightPrivate
      #
      # submissions
      #

      def delete_beta_app_review_submission_private(beta_app_review_submission_id: nil)
        params = Client.instance.build_params(filter: nil, includes: nil, limit: nil, sort: nil, cursor: nil)
        Client.instance.delete("betaAppReviewSubmissions/#{beta_app_review_submission_id}", params)
      end
    end
  end
end
