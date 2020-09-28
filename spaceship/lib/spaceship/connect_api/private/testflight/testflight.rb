require_relative 'client'

module Spaceship
  class ConnectAPI
    module TestFlightPrivate
      module API
        def test_flight_private_request_client=(test_flight_private_request_client)
          @test_flight_private_request_client = test_flight_private_request_client
        end

        def test_flight_private_request_client
          return @test_flight_private_request_client if @test_flight_private_request_client
          raise TypeError, "You need to instantiate this module with test_flight_private_request_client"
        end

        #
        # submissions
        #

        def delete_beta_app_review_submission_private(beta_app_review_submission_id: nil)
          params = test_flight_private_request_client.build_params(filter: nil, includes: nil, limit: nil, sort: nil, cursor: nil)
          test_flight_private_request_client.delete("betaAppReviewSubmissions/#{beta_app_review_submission_id}", params)
        end

        #
        # builds
        #

        def get_builds_private(filter: {}, includes: "buildBetaDetail,betaBuildMetrics", limit: 10, sort: "uploadedDate", cursor: nil)
          params = test_flight_private_request_client.build_params(filter: filter, includes: includes, limit: limit, sort: sort, cursor: cursor)
          test_flight_private_request_client.get("builds", params)
        end
      end
    end
  end
end
