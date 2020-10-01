require_relative '../model'
module Spaceship
  class ConnectAPI
    class BundleIdCapability
      include Spaceship::ConnectAPI::Model

      attr_accessor :capability_type
      attr_accessor :settings

      attr_mapping({
        "capabilityType" => "capability_type",
        "settings" => "settings"
      })

      module Type
        ICLOUD = "ICLOUD"
        IN_APP_PURCHASE = "IN_APP_PURCHASE"
        GAME_CENTER = "GAME_CENTER"
        PUSH_NOTIFICATIONS = "PUSH_NOTIFICATIONS"
        WALLET = "WALLET"
        INTER_APP_AUDIO = "INTER_APP_AUDIO"
        MAPS = "MAPS"
        ASSOCIATED_DOMAINS = "ASSOCIATED_DOMAINS"
        PERSONAL_VPN = "PERSONAL_VPN"
        APP_GROUPS = "APP_GROUPS"
        HEALTHKIT = "HEALTHKIT"
        HOMEKIT = "HOMEKIT"
        WIRELESS_ACCESSORY_CONFIGURATION = "WIRELESS_ACCESSORY_CONFIGURATION"
        APPLE_PAY = "APPLE_PAY"
        DATA_PROTECTION = "DATA_PROTECTION"
        SIRIKIT = "SIRIKIT"
        NETWORK_EXTENSIONS = "NETWORK_EXTENSIONS"
        MULTIPATH = "MULTIPATH"
        HOT_SPOT = "HOT_SPOT"
        NFC_TAG_READING = "NFC_TAG_READING"
        CLASSKIT = "CLASSKIT"
        AUTOFILL_CREDENTIAL_PROVIDER = "AUTOFILL_CREDENTIAL_PROVIDER"
        ACCESS_WIFI_INFORMATION = "ACCESS_WIFI_INFORMATION"
        APPLE_ID_AUTH = "APPLE_ID_AUTH"

        # Undocumented as of 2020-06-09
        MARZIPAN = "MARZIPAN" # Catalyst
      end

      module Settings
        ICLOUD_VERSION = "ICLOUD_VERSION"
        DATA_PROTECTION_PERMISSION_LEVEL = "DATA_PROTECTION_PERMISSION_LEVEL"
        APPLE_ID_AUTH_APP_CONSENT = "APPLE_ID_AUTH_APP_CONSENT"
      end

      module Options
        XCODE_5 = "XCODE_5"
        XCODE_6 = "XCODE_6"
        COMPLETE_PROTECTION = "COMPLETE_PROTECTION"
        PROTECTED_UNLESS_OPEN = "PROTECTED_UNLESS_OPEN"
        PROTECTED_UNTIL_FIRST_USER_AUTH = "PROTECTED_UNTIL_FIRST_USER_AUTH"
        PRIMARY_APP_CONSENT = "PRIMARY_APP_CONSENT"
      end

      def self.type
        return "bundleIdCapabilities"
      end

      #
      # Helpers
      #

      def is_type?(type)
        # JWT session returns type under "capability_type" attribute
        # Web session returns type under "id" attribute but with "P7GJR49W72_" prefixed
        return capability_type == type || id.end_with?(type)
      end

      #
      # API
      #

      def self.get(app_bundle, capability_type)
        # Comparison must be done using the same type, enforce everything to string for safety
        app_bundle.bundle_id_capabilities.find { |capability| capability.capabilityType.to_s == capability_type.to_s }
      end

      def self.create(client: nil, bundle_id_id: nil, attributes: nil, extra_relationships: nil)
        client ||= Spaceship::ConnectAPI
        resp = client.enable_bundle_id_capability(bundle_id_id: bundle_id_id, attributes: attributes, extra_relationships: extra_relationships)
        return resp.to_models.first
      end

      def delete!(client: nil)
        client ||= Spaceship::ConnectAPI
        client.disable_bundle_id_capability(bundle_id_capability: id)
      end
    end
  end
end
