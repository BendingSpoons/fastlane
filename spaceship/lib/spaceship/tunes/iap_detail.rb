require_relative '../du/upload_file'
require_relative 'iap_status'
require_relative 'iap_type'
require_relative 'tunes_base'
require_relative 'iap_subscription_pricing'

module Spaceship
  module Tunes
    class IAPDetail < TunesBase
      # @return (Spaceship::Tunes::Application) A reference to the application
      attr_accessor :application

      # @return (Integer) the IAP id
      attr_accessor :purchase_id

      # @return (Bool) if it is a news subscription
      attr_accessor :is_news_subscription

      # @return (String) the IAP Referencename
      attr_accessor :reference_name

      # @return (String) the IAP Product-Id
      attr_accessor :product_id

      # @return (String) free trial period
      attr_accessor :subscription_free_trial

      # @return (String) subscription duration
      attr_accessor :subscription_duration

      # @return (Bool) Cleared for sale flag
      attr_accessor :cleared_for_sale

      # @return (Hash) app store promotion image (optional)
      attr_accessor :merch_screenshot

      # @return (Hash) app review screenshot (required)
      attr_accessor :review_screenshot

      # @return (String) the notes for the review team
      attr_accessor :review_notes

      attr_accessor :promotion_icon

      # @return (Hash) subscription pricing target
      attr_accessor :subscription_price_target

      # @return (Hash) Relevant only for recurring subscriptions. Holds pricing related data, such
      # as subscription pricing, intro offers, etc.
      attr_accessor :raw_pricing_data

      # @return (Spaceship::Tunes::IAPSubscriptionPricing) Subscription pricing object which handle introductory pricing and subscriptions pricing
      attr_accessor :subscription_pricing

      attr_mapping({
        'adamId' => :purchase_id,
        'referenceName.value' => :reference_name,
        'productId.value' => :product_id,
        'isNewsSubscription' => :is_news_subscription,
        'pricingDurationType.value' => :subscription_duration,
        'freeTrialDurationType.value' => :subscription_free_trial,
        'clearedForSale.value' => :cleared_for_sale
      })

      def setup
        @raw_pricing_data = @raw_data["pricingData"]
        @raw_data.delete("pricingData")

        if @raw_pricing_data
          @raw_data.set(["pricingIntervals"], @raw_pricing_data["subscriptions"])
        end

        if @raw_data["addOnType"] == Tunes::IAPType::RECURRING
          raw_pricing_data = client.load_recurring_iap_pricing(app_id: application.apple_id,
                                                               purchase_id: self.purchase_id)

          @subscription_pricing = Tunes::IAPSubscriptionPricing.new(raw_pricing_data)

          @raw_data.set(["pricingIntervals"], raw_pricing_data['subscriptions'])
        end
      end

      # @return (Hash) Hash of languages
      # @example: {
      #   'de-DE': {
      #     name: "Name shown in AppStore",
      #     description: "Description of the In app Purchase"
      #
      #   }
      # }
      def versions
        parsed_versions = {}
        raw_versions = raw_data["versions"].first["details"]["value"] || []
        raw_versions.each do |localized_version|
          language = localized_version["value"]["localeCode"]
          parsed_versions[language.to_sym] = {
              name: localized_version["value"]["name"]["value"],
              description: localized_version["value"]["description"]["value"],
              id: localized_version["value"]["id"],
              status: localized_version["value"]["status"],
              locale_code: language
          }
        end
        return parsed_versions
      end

      def active_versions
        all_versions('active')
      end

      def proposed_versions
        all_versions('proposed')
      end

      # It overrides the proposed version to the active (currently on the store) version

      # @return (Hash) Hash of languages
      # @example: {
      #   'de-DE': {
      #     name: "Name shown in AppStore",
      #     description: "Description of the In app Purchase"
      #
      #   }
      # }
      def versions
        active_versions.merge(proposed_versions)
      end

      # transforms user-set versions to iTC ones
      def versions=(value = {})
        if value.kind_of?(Array)
          # input that comes from iTC api
          return
        end

        new_versions = active_versions.values

        value.each do |language, current_version|
          language = language.to_sym
          is_proposed = proposed_versions.key?(language)
          is_active = active_versions.key?(language)

          next if is_active &&
                  active_versions[language][:name] == current_version[:name] &&
                  active_versions[language][:description] == current_version[:description]

          new_versions << {
              "value" => {
                  "name" => { "value" => current_version[:name] },
                  "description" => { "value" => current_version[:description] },
                  "localeCode" => language.to_s,
                  "publicationName" => nil,
                  "status" => is_proposed ? proposed_versions[language][:status] : nil,
                  "id" => is_proposed ? proposed_versions[language][:id] : nil
              }
          }
        end

        raw_data.set(["versions"], [{
          "reviewNotes" => { value: @review_notes },
          "contentHosting" => raw_data['versions'].first['contentHosting'],
          "details" => { "value" => new_versions },
          "id" => raw_data["versions"].first["id"],
          "reviewScreenshot" => { "value" => review_screenshot },
          "merch" => raw_data["versions"].first["merch"]
        }])
      end

      # transforms user-set intervals to iTC ones
      def pricing_intervals=(value = [])
        raw_pricing_intervals =
          client.transform_to_raw_pricing_intervals(application.apple_id, self.purchase_id, value)
        raw_data.set(["pricingIntervals"], raw_pricing_intervals)
        @raw_pricing_data["subscriptions"] = raw_pricing_intervals if @raw_pricing_data
        @subscription_pricing.raw_data.set(['subscriptions'], raw_pricing_intervals) if @raw_data["addOnType"] == Tunes::IAPType::RECURRING
      end

      # @return (Array) pricing intervals
      # @example:
      #  [
      #    {
      #      country: "WW",
      #      begin_date: nil,
      #      end_date: nil,
      #      tier: 1
      #    }
      #  ]
      def pricing_intervals
        @pricing_intervals ||= (raw_data["pricingIntervals"] || @raw_pricing_data["subscriptions"] || []).map do |interval|
          {
            tier: interval["value"]["tierStem"].to_i,
            begin_date: interval["value"]["priceTierEffectiveDate"],
            end_date: interval["value"]["priceTierEndDate"],
            grandfathered: interval["value"]["grandfathered"],
            country: interval["value"]["country"]
          }
        end
      end

      def intro_offers=(value = [])
        return [] unless raw_data["addOnType"] == Spaceship::Tunes::IAPType::RECURRING
        new_intro_offers = []
        value.each do |current_intro_offer|
          new_intro_offers << {
            "value" => {
              "country" => current_intro_offer[:country],
              "durationType" => current_intro_offer[:duration_type],
              "startDate" => current_intro_offer[:start_date],
              "endDate" => current_intro_offer[:end_date],
              "numOfPeriods" => current_intro_offer[:num_of_periods],
              "offerModeType" => current_intro_offer[:offer_mode_type],
              "tierStem" => current_intro_offer[:tier_stem]
            }
          }
        end
        @subscription_pricing.raw_data.set(['introOffers'], new_intro_offers)
      end

      def intro_offers
        return [] unless raw_data["addOnType"] == Spaceship::Tunes::IAPType::RECURRING

        @intro_offers ||= (@subscription_pricing.raw_data["introOffers"] || []).map do |intro_offer|
          {
              country: intro_offer["value"]["country"],
              duration_type: intro_offer["value"]["durationType"],
              start_date: intro_offer["value"]["startDate"],
              end_date: intro_offer["value"]["endDate"],
              num_of_periods: intro_offer["value"]["numOfPeriods"],
              offer_mode_type: intro_offer["value"]["offerModeType"],
              tier_stem: intro_offer["value"]["tierStem"]
          }
        end
      end

      # @return (String) Human Readable type of the purchase
      def type
        Tunes::IAPType.get_from_string(raw_data["addOnType"])
      end

      # @return (String) Human Readable status of the purchase
      def status
        Tunes::IAPStatus.get_from_string(raw_data["versions"].first["status"])
      end

      # @return (Hash) Hash containing existing promotional image data
      def merch_screenshot
        return nil unless raw_data && raw_data["versions"] && raw_data["versions"].first && raw_data["versions"].first["merch"] && raw_data["versions"].first["merch"]["images"].first["image"]["value"]
        raw_data["versions"].first["merch"]["images"].first["image"]["value"]
      end

      # @return (Hash) Hash containing existing review screenshot data
      def review_screenshot
        return nil unless raw_data && raw_data["versions"] && raw_data["versions"].first && raw_data["versions"].first["reviewScreenshot"] && raw_data['versions'].first["reviewScreenshot"]["value"]
        raw_data['versions'].first['reviewScreenshot']['value']
      end

      # @return (Hash) Hash containing existing review screenshot data
      def promotion_icon
        return nil unless raw_data && raw_data["versions"] && raw_data["versions"].first && raw_data["versions"].first["merch"] && raw_data['versions'].first["merch"]["value"]
        raw_data['versions'].first['merch']['value']
      end

      # Saves the current In-App-Purchase
      def save!
        # Transform localization versions back to original format.
        versions_array = []
        versions.each do |language, value|
          versions_array << {
                    "value" =>  {
                      "description" => { "value" => value[:description] },
                      "name" => { "value" => value[:name] },
                      "localeCode" => language.to_s,
                      "id" => value[:id]
                    }
          }
        end

        raw_data.set(["versions"], [{ reviewNotes: { value: @review_notes }, contentHosting: raw_data['versions'].first['contentHosting'], "details" => { "value" => versions_array }, id: raw_data["versions"].first["id"], reviewScreenshot: { "value" => review_screenshot } }])

        # transform pricingDetails
        raw_pricing_intervals =
          client.transform_to_raw_pricing_intervals(application.apple_id,
                                                    self.purchase_id, pricing_intervals,
                                                    subscription_price_target)
        raw_data.set(["pricingIntervals"], raw_pricing_intervals)
        @raw_pricing_data["subscriptions"] = raw_pricing_intervals if @raw_pricing_data

        if @merch_screenshot
          # Upload App Store Promotional image (Optional)
          upload_file = UploadFile.from_path(@merch_screenshot)
          merch_data = client.upload_purchase_merch_screenshot(application.apple_id, upload_file)
          raw_data["versions"][0]["merch"] = merch_data
        end

        if @review_screenshot
          # Upload Screenshot
          upload_file = UploadFile.from_path(@review_screenshot)
          screenshot_data = client.upload_purchase_review_screenshot(application.apple_id, upload_file)
          raw_data["versions"][0]["reviewScreenshot"] = screenshot_data
        end

        if @promotion_icon
          # Upload Promotion Icon
          upload_file = UploadFile.from_path(@promotion_icon)
          promotion_data = client.upload_purchase_promotion_icon(application.apple_id, upload_file)

          icons = raw_data["versions"][0]["merch"]["images"]
          active_icon = icons.select { |icon| icon["status"] == 'active' }
          proposed_icon = icons.select { |icon| icon["status"] == 'proposed' }

          new_icon = {
              "id" => proposed_icon.empty? ? nil : proposed_icon[0]["id"],
              "image" => {
                  "value" => promotion_data["value"],
                  "isEditable" => true,
                  "isRequired" => false,
                  "errorKeys" => nil
              },
              "status" => proposed_icon.empty? ? nil : proposed_icon[0]["status"]
          }

          raw_data["versions"][0]["merch"]["images"] = []
          raw_data["versions"][0]["merch"]["images"] << active_icon[0] unless active_icon.empty?
          raw_data["versions"][0]["merch"]["images"] << new_icon
        end
        # Update the Purchase
        client.update_iap!(app_id: application.apple_id, purchase_id: self.purchase_id, data: raw_data)

        # Update pricing for a recurring subscription.
        if @raw_data["addOnType"] == Spaceship::Tunes::IAPType::RECURRING
          client.update_recurring_iap_pricing!(app_id: application.apple_id, purchase_id: self.purchase_id,
                                                             pricing_intervals: raw_data["pricingIntervals"])

          client.update_recurring_iap_pricing_intro_offers!(app_id: application.apple_id, purchase_id: self.purchase_id,
                                                            intro_offers: self.subscription_pricing.raw_data["introOffers"])
        end
      end

      # Deletes In-App-Purchase
      def delete!
        client.delete_iap!(app_id: application.apple_id, purchase_id: self.purchase_id)
      end

      # Retrieves the actual prices for an iap.
      #
      # @return ([]) An empty array
      #   if the iap is not yet cleared for sale
      # @return ([Spaceship::Tunes::PricingInfo]) An array of pricing infos from the same pricing tier
      #   if the iap uses world wide pricing
      # @return ([Spaceship::Tunes::IAPSubscriptionPricingInfo]) An array of pricing infos from multple subscription pricing tiers
      #   if the iap uses territorial pricing
      def pricing_info
        return [] unless cleared_for_sale
        return world_wide_pricing_info if world_wide_pricing?
        territorial_pricing_info
      end

      private

      # @return (Hash) Hash of languages
      # @example: {
      #   'de-DE': {
      #     id: nil,
      #     locale_code: "de-DE",
      #     name: "Name shown in AppStore",
      #     description: "Description of the In app Purchase"
      #     status: 'active'
      #     publication_name: nil
      #   }
      # }
      def all_versions(status = 'active')
        parsed_versions = {}
        raw_versions = raw_data["versions"].first["details"]["value"]
        raw_versions.each do |localized_version|
          next if status != localized_version["value"]["status"]
          language = localized_version["value"]["localeCode"]
          parsed_versions[language.to_sym] = {
              id: localized_version["value"]["id"],
              locale_code: localized_version["value"]["localeCode"],
              name: localized_version["value"]["name"]["value"],
              description: localized_version["value"]["description"]["value"],
              status: localized_version["value"]["status"],
              publication_name: localized_version["value"]["publicationName"]
          }
        end

        parsed_versions
      end

      # Checks wheather an iap uses world wide or territorial pricing.
      #
      # @return (true, false)
      def world_wide_pricing?
        pricing_intervals.fetch(0, {})[:country] == "WW"
      end

      # Maps a single pricing interval to pricing infos.
      #
      # @return ([Spaceship::Tunes::PricingInfo]) An array of pricing infos from the same tier
      def world_wide_pricing_info
        client
          .pricing_tiers
          .find { |p| p.tier_stem == pricing_intervals.first[:tier].to_s }
          .pricing_info
      end

      # Maps pricing intervals to their respective subscription pricing infos.
      #
      # @return ([Spaceship::Tunes::IAPSubscriptionPricingInfo]) An array of subscription pricing infos
      def territorial_pricing_info
        pricing_matrix = client.subscription_pricing_tiers(application.apple_id)
        pricing_intervals.map do |interval|
          pricing_matrix
            .find { |p| p.tier_stem == interval[:tier].to_s }
            .pricing_info
            .find { |i| i.country_code == interval[:country] }
        end
      end
    end
  end
end
