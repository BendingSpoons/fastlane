require 'fastimage'

require_relative 'module'
require 'spaceship/connect_api/models/app_preview_set'

module Deliver
  # AppPreview represents one app preview for one specific locale and
  # device type.
  class AppPreview
    module ScreenSize
      # iPhone 4
      IOS_35 = "iOS-3.5-in"
      # iPhone 5
      IOS_40 = "iOS-4-in"
      # iPhone 6, 7, & 8
      IOS_47 = "iOS-4.7-in"
      # iPhone 6 Plus, 7 Plus, & 8 Plus
      IOS_55 = "iOS-5.5-in"
      # iPhone XS
      IOS_58 = "iOS-5.8-in"
      # iPhone XS Max
      IOS_65 = "iOS-6.5-in"

      # iPad
      IOS_IPAD = "iOS-iPad"
      # iPad 10.5
      IOS_IPAD_10_5 = "iOS-iPad-10.5"
      # iPad 11
      IOS_IPAD_11 = "iOS-iPad-11"
      # iPad Pro
      IOS_IPAD_PRO = "iOS-iPad-Pro"
      # iPad Pro (12.9-inch) (3rd generation)
      IOS_IPAD_PRO_12_9 = "iOS-iPad-Pro-12.9"

      # Mac
      MAC = "Mac"
    end

    # @return [Deliver::ScreenSize] the screen size (device type)
    #  specified at {Deliver::ScreenSize}
    attr_accessor :screen_size

    attr_accessor :path

    attr_accessor :language

    # @param path (String) path to the app preview file
    # @param language (String) Language of this app preview (e.g. English)
    # @param screen_size (Deliver::AppPreview::ScreenSize) the screen size
    def initialize(path, language, screen_size)
      self.path = path
      self.language = language
      self.screen_size = screen_size

      UI.error("Looks like the app preview given (#{path}) does not match the requirements of #{screen_size}") unless self.is_valid?
    end

    # The iTC API requires a different notation for the device
    def device_type
      matching = {
          ScreenSize::IOS_35 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPHONE_35,
          ScreenSize::IOS_40 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPHONE_40,
          ScreenSize::IOS_47 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPHONE_47, # also 7 & 8
          ScreenSize::IOS_55 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPHONE_55, # also 7 Plus & 8 Plus
          ScreenSize::IOS_58 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPHONE_58,
          ScreenSize::IOS_65 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPHONE_65,
          ScreenSize::IOS_IPAD => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPAD_97,
          ScreenSize::IOS_IPAD_10_5 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPAD_105,
          ScreenSize::IOS_IPAD_11 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPAD_PRO_3GEN_11,
          ScreenSize::IOS_IPAD_PRO => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPAD_PRO_129,
          ScreenSize::IOS_IPAD_PRO_12_9 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPAD_PRO_3GEN_129,
          ScreenSize::MAC => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::DESKTOP
      }
      return matching[self.screen_size]
    end

    # Nice name
    def formatted_name
      matching = {
          ScreenSize::IOS_35 => "iPhone 4",
          ScreenSize::IOS_40 => "iPhone 5",
          ScreenSize::IOS_47 => "iPhone 6", # also 7 & 8
          ScreenSize::IOS_55 => "iPhone 6 Plus", # also 7 Plus & 8 Plus
          ScreenSize::IOS_58 => "iPhone XS",
          ScreenSize::IOS_65 => "iPhone XS Max",
          ScreenSize::IOS_IPAD => "iPad",
          ScreenSize::IOS_IPAD_10_5 => "iPad 10.5",
          ScreenSize::IOS_IPAD_11 => "iPad 11",
          ScreenSize::IOS_IPAD_PRO => "iPad Pro",
          ScreenSize::IOS_IPAD_PRO_12_9 => "iPad Pro (12.9-inch) (3rd generation)",
          ScreenSize::MAC => "Mac"
      }
      return matching[self.screen_size]
    end

    # Validates the given app previews (format)
    def is_valid?
      %w(mov MOV).include?(self.path.split(".").last)
    end

    # reference: https://help.apple.com/app-store-connect/#/devd274dd925
    def self.devices
      # This list does not include iPad Pro 12.9-inch (3rd generation)
      # because it has same resoluation as IOS_IPAD_PRO and will clobber
      return {
        ScreenSize::IOS_65 => [
          [1242, 2688],
          [2688, 1242]
        ],
        ScreenSize::IOS_58 => [
          [1125, 2436],
          [2436, 1125]
        ],
        ScreenSize::IOS_55 => [
          [1242, 2208],
          [2208, 1242]
        ],
        ScreenSize::IOS_47 => [
          [750, 1334],
          [1334, 750]
        ],
        ScreenSize::IOS_40 => [
          [640, 1096],
          [640, 1136],
          [1136, 600],
          [1136, 640]
        ],
        ScreenSize::IOS_35 => [
          [640, 920],
          [640, 960],
          [960, 600],
          [960, 640]
        ],
        ScreenSize::IOS_IPAD => [ # 9.7 inch
          [1024, 748],
          [1024, 768],
          [2048, 1496],
          [2048, 1536],
          [768, 1004], # portrait without status bar
          [768, 1024],
          [1536, 2008], # portrait without status bar
          [1536, 2048]
        ],
        ScreenSize::IOS_IPAD_10_5 => [
          [1668, 2224],
          [2224, 1668]
        ],
        ScreenSize::IOS_IPAD_11 => [
          [1668, 2388],
          [2388, 1668]
        ],
        ScreenSize::IOS_IPAD_PRO => [
          [2732, 2048],
          [2048, 2732]
        ],
        ScreenSize::MAC => [
          [1280, 800],
          [1440, 900],
          [2560, 1600],
          [2880, 1800]
        ]
      }
    end
  end

  PreviewScreenSize = AppPreview::ScreenSize
end
