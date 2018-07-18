require_relative 'iap_type'
require_relative 'tunes_base'

module Spaceship
  module Tunes
    class AppAddon < TunesBase
      # @return (Spaceship::Tunes::Application) A reference to the application
      #   this addon is for
      attr_accessor :application

      # @return (String) The identifier of this Addon, provided by iTunes Connect
      # @example
      #   "1013943394"
      attr_accessor :addon_id

      # @return (String) The type of the Addon.
      # @example
      #   "ITC.addons.type.subscription"
      attr_accessor :addon_type

      # @return (Bool) Can the Addon be deleted?
      attr_accessor :can_delete

      # @return (String) Status of Addon in ITunes Connect
      # @example
      #   "readyToSubmit"
      attr_accessor :itc_status

      # @return (String) Name of Addon (Reference Name)
      # @example
      #   "My Product Name"
      attr_accessor :name

      # @return (String) Product Id in iTunes Connect
      # @example
      #   "com.company.app.MyProduct1"
      attr_accessor :vendor_id

      # @return (Array) A list of all versions for this addon
      # @example
      #   [
      #      {
      #         "itunesConnectStatus" : "readyToSubmit",
      #         "canSubmit" : true,
      #         "screenshotUrl": "https://is3-ssl.mzstatic.com/image/thumb/Purple3/v4/42/45/f2/4245f2ee-3a37-a34d-a659-1f5f403ab2fe/pr_source.png/500x500bb-80.png",
      #         "issuesCount" : 0
      #      }
      #   ]
      attr_reader :versions

      # @return (Bool) Can the Addon be submit in the next version?
      attr_accessor :can_submit_in_the_next_version

      attr_mapping(
        'adamId' => :addon_id,
        'addOnType' => :addon_type,
        'canDeleteAddOn' => :can_delete,
        'iTunesConnectStatus' => :itc_status,
        'referenceName' => :name,
        'vendorId' => :vendor_id,
        'versions' => :versions,
        'itcsubmitNextVersion' => :can_submit_in_the_next_version
      )

      class << self
        # Create a new object based on a hash.
        # This is used to create a new object based on the server response.
        def factory(attrs)
          obj = self.new(attrs)
          return obj
        end
      end

      # Delete current addon
      def delete!
        client.delete_addon!(self)
      end

      # Return true if this addon can be submitted
      def can_submit?
        return false if addon_type == "ITC.addons.type.freeSubscription"
        !!versions.find { |version| version['canSubmit'] }
      end

      # Submit iap addon
      def submit!
        client.submit_addons!(application.apple_id, [raw_data])
      end

      # @return (String) Human Readable type of the purchase
      def type
        Tunes::IAPType.get_from_string(raw_data["addOnType"])
      end
    end
  end
end
