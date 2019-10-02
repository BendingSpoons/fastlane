require 'spaceship/connect_api/provisioning/client'

module Spaceship
  class ConnectAPI
    module Provisioning
      module API
        def provisioning_request_client=(provisioning_request_client)
          @provisioning_request_client = provisioning_request_client
        end

        def provisioning_request_client
          return @provisioning_request_client if @provisioning_request_client
          raise TypeError, "You need to instantiate this module with provisioning_request_client"
        end

        #
        # bundleIds
        #

        def get_bundle_ids(filter: {}, includes: nil, limit: nil, sort: nil)
          params = provisioning_request_client.build_params(filter: filter, includes: includes, limit: limit, sort: sort)
          provisioning_request_client.get("bundleIds", params)
        end

        def get_bundle_id(bundle_id_id: {}, includes: nil)
          params = provisioning_request_client.build_params(filter: nil, includes: includes, limit: nil, sort: nil)
          provisioning_request_client.get("bundleIds/#{bundle_id_id}", params)
        end

        def post_bundle_id(name:, platform:, identifier:, seed_id:)
          attributes = {
            name: name,
            platform: platform,
            identifier: identifier,
            seedId: seed_id
          }

          body = {
            data: {
              attributes: attributes,
              type: "bundleIds"
            }
          }

          provisioning_request_client.post("bundleIds", body)
        end

        #
        # bundleIdCapability
        #

        def get_bundle_id_capabilities(bundle_id_id:, includes: nil, limit: nil, sort: nil)
          params = provisioning_request_client.build_params(filter: nil, includes: includes, limit: limit, sort: sort)
          provisioning_request_client.get("bundleIds/#{bundle_id_id}/bundleIdCapabilities", params)
        end

        def post_bundle_id_capability(bundle_id_id:, capability_type:, settings: [])
          body = {
            data: {
              attributes: {
                capabilityType: capability_type,
                settings: settings
              },
              type: "bundleIdCapabilities",
              relationships: {
                bundleId: {
                  data: {
                    type: "bundleIds",
                    id: bundle_id_id
                  }
                }
              }
            }
          }

          provisioning_request_client.post("bundleIdCapabilities", body)
        end

        def delete_bundle_id_capability(bundle_id_capability_id:)
          provisioning_request_client.delete("bundleIdCapabilities/#{bundle_id_capability_id}")
        end

        #
        # certificates
        #

        def get_certificates(filter: {}, includes: nil, limit: nil, sort: nil)
          params = provisioning_request_client.build_params(filter: filter, includes: includes, limit: limit, sort: sort)
          provisioning_request_client.get("certificates", params)
        end

        def get_certificate(certificate_id: nil, includes: nil)
          params = provisioning_request_client.build_params(filter: nil, includes: includes, limit: nil, sort: nil)
          provisioning_request_client.get("certificates/#{certificate_id}", params)
        end

        def post_certificate(attributes: {})
          body = {
            data: {
              attributes: attributes,
              type: "certificates"
            }
          }

          provisioning_request_client.post("certificates", body)
        end

        def delete_certificate(certificate_id: nil)
          raise "Certificate id is nil" if certificate_id.nil?

          provisioning_request_client.delete("certificates/#{certificate_id}")
        end

        #
        # devices
        #

        def get_devices(profile_id: nil, filter: {}, includes: nil, limit: nil, sort: nil)
          params = provisioning_request_client.build_params(filter: filter, includes: includes, limit: limit, sort: sort)
          if profile_id.nil?
            provisioning_request_client.get("devices", params)
          else
            provisioning_request_client.get("profiles/#{profile_id}/devices", params)
          end
        end

        def post_device(name: nil, platform: nil, udid: nil)
          attributes = {
            name: name,
            platform: platform,
            udid: udid
          }

          body = {
            data: {
              attributes: attributes,
              type: "devices"
            }
          }

          provisioning_request_client.post("devices", body)
        end

        #
        # profiles
        #

        def get_profiles(filter: {}, includes: nil, limit: nil, sort: nil)
          params = provisioning_request_client.build_params(filter: filter, includes: includes, limit: limit, sort: sort)
          provisioning_request_client.get("profiles", params)
        end

        def post_profiles(bundle_id_id: nil, certificates: nil, devices: nil, attributes: {})
          body = {
            data: {
              attributes: attributes,
              type: "profiles",
              relationships: {
                bundleId: {
                  data: {
                    type: "bundleIds",
                    id: bundle_id_id
                  }
                },
                certificates: {
                  data: certificates.map do |certificate|
                    {
                      type: "certificates",
                      id: certificate
                    }
                  end
                },
                devices: {
                  data: (devices || []).map do |device|
                    {
                      type: "devices",
                      id: device
                    }
                  end
                }
              }
            }
          }

          provisioning_request_client.post("profiles", body)
        end

        def delete_profile(profile_id: nil)
          raise "Profile id is nil" if profile_id.nil?

          provisioning_request_client.delete("profiles/#{profile_id}")
        end
      end

      #
      # capabilities
      #

      def disable_bundle_id_capability(bundle_id_capability: nil)
        # Safety check: you can't disable a capability that is already disable (Apple doesn't know idempotency)
        Client.instance.delete("bundleIdCapabilities/#{bundle_id_capability}")
      rescue Spaceship::UnexpectedResponse
        return
      end

      def enable_bundle_id_capability(bundle_id_id: nil, attributes: {}, extra_relationships: nil)
        relationships = {
            bundleId: {
                data: {
                    type: "bundleIds",
                    id: bundle_id_id
                }
            }
        }
        relationships.update(extra_relationships) if extra_relationships

        body = {
            data: {
                type: "bundleIdCapabilities",
                attributes: attributes,
                relationships: relationships
            }
        }

        Client.instance.post("bundleIdCapabilities", body)
      end

      def enable_sign_in_with_apple_primary(bundle_id_id: nil)
        enable_sign_in_with_apple(bundle_id_id: bundle_id_id, consent_type: "PRIMARY_APP_CONSENT")
      end

      def enable_sign_in_with_apple_related(bundle_id_id: nil, related_bundle_id_id: nil)
        association = {
            key: "TIBURON_PRIMARY_BUNDLEID",
            allowedInstances: "MULTIPLE",
            relationshipName: "appConsentBundleId",
            relationshipType: "bundleIds"
        }
        relationships = {
            appConsentBundleId: {
                data: {
                    type: "bundleIds",
                    id: related_bundle_id_id
                }
            }
        }
        enable_sign_in_with_apple(bundle_id_id: bundle_id_id, consent_type: "RELATED_APP_CONSENT", associations: [association], extra_relationships: relationships)
      end

      def disable_sign_in_with_apple(bundle_id_id: nil)
        disable_bundle_id_capability(bundle_id_capability: "#{bundle_id_id}_APPLE_ID_AUTH")
      end

      # @private

      def enable_sign_in_with_apple(bundle_id_id: nil, consent_type: nil, associations: nil, extra_relationships: {})
        consent_options = {}
        consent_options[:key] = consent_type
        consent_options[:associations] = associations if associations

        consent = {
            key: "TIBURON_APP_CONSENT",
            options: [consent_options]
        }
        settings = [consent]

        attributes = {
            capabilityType: "APPLE_ID_AUTH",
            settings: settings
        }

        enable_bundle_id_capability(bundle_id_id: bundle_id_id, attributes: attributes, extra_relationships: extra_relationships)
      end
    end
  end
end
