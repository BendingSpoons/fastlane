require 'spaceship/connect_api/testflight/client'

module Spaceship
  class ConnectAPI
    module TestFlight
      #
      # apps
      #

      def get_apps(filter: {}, includes: nil, limit: nil, sort: nil)
        params = Client.instance.build_params(filter: filter, includes: includes, limit: limit, sort: sort)
        Client.instance.get("apps", params)
      end

      def get_app(app_id: nil, includes: nil)
        params = Client.instance.build_params(filter: nil, includes: includes, limit: nil, sort: nil)
        Client.instance.get("apps/#{app_id}", params)
      end

      #
      # betaAppLocalizations
      #

      def get_beta_app_localizations(filter: {}, includes: nil, limit: nil, sort: nil)
        params = Client.instance.build_params(filter: filter, includes: includes, limit: limit, sort: sort)
        Client.instance.get("betaAppLocalizations", params)
      end

      def post_beta_app_localizations(app_id: nil, attributes: {})
        body = {
          data: {
            attributes: attributes,
            type: "betaAppLocalizations",
            relationships: {
              app: {
                data: {
                  type: "apps",
                  id: app_id
                }
              }
            }
          }
        }

        Client.instance.post("betaAppLocalizations", body)
      end

      def patch_beta_app_localizations(localization_id: nil, attributes: {})
        body = {
          data: {
            attributes: attributes,
            id: localization_id,
            type: "betaAppLocalizations"
          }
        }

        Client.instance.patch("betaAppLocalizations/#{localization_id}", body)
      end

      #
      # betaAppReviewDetails
      #

      def get_beta_app_review_detail(filter: {}, includes: nil, limit: nil, sort: nil)
        params = Client.instance.build_params(filter: filter, includes: includes, limit: limit, sort: sort)
        Client.instance.get("betaAppReviewDetails", params)
      end

      def patch_beta_app_review_detail(app_id: nil, attributes: {})
        body = {
          data: {
            attributes: attributes,
            id: app_id,
            type: "betaAppReviewDetails"
          }
        }

        Client.instance.patch("betaAppReviewDetails/#{app_id}", body)
      end

      #
      # betaAppReviewSubmissions
      #

      def get_beta_app_review_submissions(filter: {}, includes: nil, limit: nil, sort: nil, cursor: nil)
        params = Client.instance.build_params(filter: filter, includes: includes, limit: limit, sort: sort, cursor: cursor)
        Client.instance.get("betaAppReviewSubmissions", params)
      end

      def post_beta_app_review_submissions(build_id: nil)
        body = {
          data: {
            type: "betaAppReviewSubmissions",
            relationships: {
              build: {
                data: {
                  type: "builds",
                  id: build_id
                }
              }
            }
          }
        }

        Client.instance.post("betaAppReviewSubmissions", body)
      end

      # BSP note: this does NOT work at the moment, as the public ConnectAPI doesn't support this feature
      def delete_beta_app_review_submission(beta_app_review_submission_id: nil)
        params = Client.instance.build_params(filter: nil, includes: nil, limit: nil, sort: nil, cursor: nil)
        Client.instance.delete("betaAppReviewSubmissions/#{beta_app_review_submission_id}", params)
      end

      #
      # betaBuildLocalizations
      #

      def get_beta_build_localizations(filter: {}, includes: nil, limit: nil, sort: nil)
        params = Client.instance.build_params(filter: filter, includes: includes, limit: limit, sort: sort)
        Client.instance.get("betaBuildLocalizations", params)
      end

      def post_beta_build_localizations(build_id: nil, attributes: {})
        body = {
          data: {
            attributes: attributes,
            type: "betaBuildLocalizations",
            relationships: {
              build: {
                data: {
                  type: "builds",
                  id: build_id
                }
              }
            }
          }
        }

        Client.instance.post("betaBuildLocalizations", body)
      end

      def patch_beta_build_localizations(localization_id: nil, feedbackEmail: nil, attributes: {})
        body = {
          data: {
            attributes: attributes,
            id: localization_id,
            type: "betaBuildLocalizations"
          }
        }

        Client.instance.patch("betaBuildLocalizations/#{localization_id}", body)
      end

      #
      # betaBuildMetrics
      #

      def get_beta_build_metrics(filter: {}, includes: nil, limit: nil, sort: nil)
        params = Client.instance.build_params(filter: filter, includes: includes, limit: limit, sort: sort)
        Client.instance.get("betaBuildMetrics", params)
      end

      #
      # betaGroups
      #

      def get_beta_groups(filter: {}, includes: nil, limit: nil, sort: nil)
        params = Client.instance.build_params(filter: filter, includes: includes, limit: limit, sort: sort)
        Client.instance.get("betaGroups", params)
      end

      def add_beta_group(app_id, name, public_link_enabled: false, public_link_limit: nil, public_link_limit_enabled: false)
        attributes = {
            name: name,
            publicLinkEnabled: public_link_enabled,
            publicLinkLimitEnabled: public_link_limit_enabled
        }
        attributes[:publicLinkLimit] = public_link_limit if public_link_limit

        body = {
            data: {
                attributes: attributes,
                type: "betaGroups",
                relationships: {
                    app: {
                        data: {
                            type: "apps",
                            id: app_id
                        }
                    }
                }
            }
        }

        Client.instance.post("betaGroups", body)
      end

      def update_beta_group(beta_group_id, public_link_enabled: nil, public_link_limit_enabled: nil, public_link_limit: nil)
        attributes = {}
        attributes[:publicLinkEnabled] = public_link_enabled unless public_link_enabled.nil?
        attributes[:publicLinkLimit] = public_link_limit unless public_link_limit.nil?
        attributes[:publicLinkLimitEnabled] = public_link_limit_enabled unless public_link_limit_enabled.nil?

        body = {
            data: {
                attributes: attributes,
                id: beta_group_id,
                type: "betaGroups"
            }
        }

        Client.instance.patch("betaGroups/#{beta_group_id}", body)
      end

      def add_beta_groups_to_build(build_id: nil, beta_group_ids: [])
        body = {
          data: beta_group_ids.map do |id|
            {
              type: "betaGroups",
              id: id
            }
          end
        }

        Client.instance.post("builds/#{build_id}/relationships/betaGroups", body)
      end

      def delete_beta_groups_to_build(build_id: nil, beta_group_ids: [])
        body = {
            data: beta_group_ids.map do |id|
              {
                  type: "betaGroups",
                  id: id
              }
            end
        }

        Client.instance.delete("builds/#{build_id}/relationships/betaGroups", {}, body)
      end

      #
      # betaTesters
      #

      def get_beta_testers(filter: {}, includes: nil, limit: nil, sort: nil)
        params = Client.instance.build_params(filter: filter, includes: includes, limit: limit, sort: sort)
        Client.instance.get("betaTesters", params)
      end

      # beta_testers - [{email: "", firstName: "", lastName: ""}]
      # BSP comment: DO NOT USE THIS, IT'S BROKEN
      def post_bulk_beta_tester_assignments(beta_group_id: nil, beta_testers: nil)
        beta_testers || []

        beta_testers.map do |tester|
          tester[:errors] = []
        end

        body = {
          data: {
            attributes: {
              betaTesters: beta_testers
            },
            relationships: {
              betaGroup: {
                data: {
                  type: "betaGroups",
                  id: beta_group_id
                }
              }
            },
            type: "bulkBetaTesterAssignments"
          }
        }

        Client.instance.post("bulkBetaTesterAssignments", body)
      end

      def delete_beta_tester_from_apps(beta_tester_id: nil, app_ids: [])
        body = {
          data: app_ids.map do |id|
            {
              type: "apps",
              id: id
            }
          end
        }

        delete("betaTesters/#{beta_tester_id}/relationships/apps", nil, body)
      end

      # BSP method, completes the beta tester management functionality
      def add_beta_tester_to_beta_groups(beta_tester_id: nil, beta_group_ids: [])
        body = {
            data: beta_group_ids.map do |id|
              {
                  type: "betaGroups",
                  id: id
              }
            end
        }

        Client.instance.post("betaTesters/#{beta_tester_id}/relationships/betaGroups", body)
      end

      def delete_beta_tester_from_beta_groups(beta_tester_id: nil, beta_group_ids: [])
        body = {
          data: beta_group_ids.map do |id|
            {
              type: "betaGroups",
              id: id
            }
          end
        }

        delete("betaTesters/#{beta_tester_id}/relationships/betaGroups", nil, body)
      end

      #
      # betaTesterMetrics
      #

      def get_beta_tester_metrics(filter: {}, includes: nil, limit: nil, sort: nil)
        params = Client.instance.build_params(filter: filter, includes: includes, limit: limit, sort: sort)
        Client.instance.get("betaTesterMetrics", params)
      end

      #
      # builds
      #

      def get_builds(filter: {}, includes: "buildBetaDetail", limit: 10, sort: "uploadedDate", cursor: nil)
        params = Client.instance.build_params(filter: filter, includes: includes, limit: limit, sort: sort, cursor: cursor)
        Client.instance.get("builds", params)
      end

      def get_build(build_id: nil, includes: nil)
        params = Client.instance.build_params(filter: nil, includes: includes, limit: nil, sort: nil, cursor: nil)
        Client.instance.get("builds/#{build_id}", params)
      end

      def patch_builds(build_id: nil, attributes: {})
        body = {
          data: {
            attributes: attributes,
            id: build_id,
            type: "builds"
          }
        }

        Client.instance.patch("builds/#{build_id}", body)
      end

      #
      # buildBetaDetails
      #

      def get_build_beta_details(filter: {}, includes: nil, limit: nil, sort: nil)
        params = Client.instance.build_params(filter: filter, includes: includes, limit: limit, sort: sort)
        Client.instance.get("buildBetaDetails", params)
      end

      def patch_build_beta_details(build_beta_details_id: nil, attributes: {})
        body = {
          data: {
            attributes: attributes,
            id: build_beta_details_id,
            type: "buildBetaDetails"
          }
        }

        Client.instance.patch("buildBetaDetails/#{build_beta_details_id}", body)
      end

      #
      # buildDeliveries
      #

      def get_build_deliveries(filter: {}, includes: nil, limit: nil, sort: nil)
        params = Client.instance.build_params(filter: filter, includes: includes, limit: limit, sort: sort)
        Client.instance.get("buildDeliveries", params)
      end

      #
      # preReleaseVersions
      #

      def get_pre_release_versions(filter: {}, includes: nil, limit: nil, sort: nil)
        params = Client.instance.build_params(filter: filter, includes: includes, limit: limit, sort: sort)
        Client.instance.get("preReleaseVersions", params)
      end
    end
  end
end
