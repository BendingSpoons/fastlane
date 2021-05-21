# This file contains the BSP modified implementation for screenshots uploading.
# The heavy changes made by us are not compatible with the later work done on
# the screenshot uploading by Fastlane. As such, they have been moved here so
# that the original file can continue to follow what has been done in vanilla
# Fastlane in order to have have less conflicts during a rebase.

require 'parallel'
require 'spaceship/tunes/tunes'
require 'digest/md5'

require_relative 'app_screenshot'
require_relative 'module'
require_relative 'loader'
require_relative 'utils'

module Deliver
  # upload screenshots to App Store Connect
  class BSPUploadScreenshots
    def upload(options, screenshots, max_n_threads = 16)
      return if options[:skip_screenshots]
      return if options[:edit_live]

      app = options[:app]

      platform = Spaceship::ConnectAPI::Platform.map(options[:platform])
      version = app.get_edit_app_store_version(platform: platform)
      UI.user_error!("Could not find a version to edit for app '#{app.name}' for '#{platform}'") unless version

      UI.important("Will begin uploading snapshots for '#{version.version_string}' on App Store Connect")

      UI.message("Starting with the upload of screenshots...")
      screenshots_per_language = screenshots.group_by(&:language)

      localizations = version.get_app_store_version_localizations

      if options[:overwrite_screenshots]
        delete_screenshots(localizations, screenshots_per_language, max_n_threads)
      end

      # Finding languages to enable
      languages = screenshots_per_language.keys
      locales_to_enable = languages - localizations.map(&:locale)

      if locales_to_enable.count > 0
        lng_text = "language"
        lng_text += "s" if locales_to_enable.count != 1
        Helper.show_loading_indicator("Activating #{lng_text} #{locales_to_enable.join(', ')}...")

        locales_to_enable.each do |locale|
          version.create_app_store_version_localization(attributes: {
            locale: locale
          })
        end

        Helper.hide_loading_indicator

        # Refresh version localizations
        localizations = version.get_app_store_version_localizations
      end

      upload_screenshots(screenshots_per_language, localizations, options, max_n_threads)
    end

    def delete_screenshots(localizations, screenshots_per_language, max_n_threads, tries: 5)
      tries -= 1

      # Get localizations on version
      n_threads = [max_n_threads, localizations.length].min
      Parallel.each(localizations, in_threads: n_threads) do |localization|
        # Only delete screenshots if trying to upload
        next unless screenshots_per_language.keys.include?(localization.locale)

        # Iterate over all screenshots for each set and delete
        screenshot_sets = localization.get_app_screenshot_sets

        # Multi threading delete on single localization
        screenshot_sets.each do |screenshot_set|
          UI.message("Removing all previously uploaded screenshots for '#{localization.locale}' '#{screenshot_set.screenshot_display_type}'...")
          screenshot_set.app_screenshots.each do |screenshot|
            UI.verbose("Deleting screenshot - #{localization.locale} #{screenshot_set.screenshot_display_type} #{screenshot.id}")
            Deliver.retry_api_call do
              screenshot.delete!
              UI.verbose("Deleted screenshot - #{localization.locale} #{screenshot_set.screenshot_display_type} #{screenshot.id}")
            end
          end
        end
      end

      # Verify all screenshots have been deleted
      # Sometimes API requests will fail but screenshots will still be deleted
      count = count_screenshots(localizations)
      UI.important("Number of screenshots not deleted: #{count}")
      if count > 0
        if tries.zero?
          UI.user_error!("Failed verification of all screenshots deleted... #{count} screenshot(s) still exist")
        else
          UI.error("Failed to delete all screenshots... Tries remaining: #{tries}")
          delete_screenshots(localizations, screenshots_per_language, tries: tries)
        end
      else
        UI.message("Successfully deleted all screenshots")
      end
    end

    def count_screenshots(localizations)
      count = 0
      localizations.each do |localization|
        screenshot_sets = localization.get_app_screenshot_sets
        screenshot_sets.each do |screenshot_set|
          count += screenshot_set.app_screenshots.size
        end
      end

      return count
    end

    def upload_screenshots(screenshots_per_language, localizations, options, max_n_threads)
      # Check if should wait for processing
      # Default to waiting if submitting for review (since needed for submission)
      # Otherwise use enviroment variable
      if ENV["DELIVER_SKIP_WAIT_FOR_SCREENSHOT_PROCESSING"].nil?
        wait_for_processing = options[:submit_for_review]
        UI.verbose("Setting wait_for_processing from ':submit_for_review' option")
      else
        UI.verbose("Setting wait_for_processing from 'DELIVER_SKIP_WAIT_FOR_SCREENSHOT_PROCESSING' environment variable")
        wait_for_processing = !FastlaneCore::Env.truthy?("DELIVER_SKIP_WAIT_FOR_SCREENSHOT_PROCESSING")
      end

      if wait_for_processing
        UI.important("Will wait for screenshot image processing")
        UI.important("Set env DELIVER_SKIP_WAIT_FOR_SCREENSHOT_PROCESSING=true to skip waiting for screenshots to process")
      else
        UI.important("Skipping the wait for screenshot image processing (which may affect submission)")
        UI.important("Set env DELIVER_SKIP_WAIT_FOR_SCREENSHOT_PROCESSING=false to wait for screenshots to process")
      end

      # Upload screenshots
      indized = {} # per language and device type

      n_threads = [max_n_threads, screenshots_per_language.length].min
      Parallel.each(screenshots_per_language, in_threads: n_threads) do |language, screenshots_for_language|
        # Find localization to upload screenshots to
        localization = localizations.find do |l|
          l.locale == language
        end

        unless localization
          UI.error("Couldn't find localization on version for #{language}")
          next
        end

        indized[localization.locale] ||= {}

        # Create map to find screenshot set to add screenshot to
        app_screenshot_sets_map = {}
        app_screenshot_sets = localization.get_app_screenshot_sets
        app_screenshot_sets.each do |app_screenshot_set|
          app_screenshot_sets_map[app_screenshot_set.screenshot_display_type] = app_screenshot_set

          # Set initial screnshot count
          indized[localization.locale][app_screenshot_set.screenshot_display_type] ||= {
            count: app_screenshot_set.app_screenshots.size,
            checksums: []
          }

          checksums = app_screenshot_set.app_screenshots.map(&:source_file_checksum).uniq
          indized[localization.locale][app_screenshot_set.screenshot_display_type][:checksums] = checksums
        end

        UI.message("Uploading #{screenshots_for_language.length} screenshots for language #{language}")
        screenshots_for_language.each do |screenshot|
          Deliver.retry_api_call do
            display_type = screenshot.device_type
            set = app_screenshot_sets_map[display_type]

            if display_type.nil?
              UI.error("Error... Screenshot size #{screenshot.screen_size} not valid for App Store Connect")
              next
            end

            unless set
              set = localization.create_app_screenshot_set(attributes: {
                screenshotDisplayType: display_type
              })
              app_screenshot_sets_map[display_type] = set

              indized[localization.locale][set.screenshot_display_type] = {
                count: 0,
                checksums: []
              }
            end

            index = indized[localization.locale][set.screenshot_display_type][:count]

            if index >= 10
              UI.error("Too many screenshots found for device '#{screenshot.device_type}' in '#{screenshot.language}', skipping this one (#{screenshot.path})")
              next
            end

            bytes = File.binread(screenshot.path)
            checksum = Digest::MD5.hexdigest(bytes)
            duplicate = indized[localization.locale][set.screenshot_display_type][:checksums].include?(checksum)

            if duplicate
              UI.message("Previous uploaded. Skipping '#{screenshot.path}'...")
            else
              indized[localization.locale][set.screenshot_display_type][:count] += 1
              UI.message("Uploading '#{screenshot.path}'...")
              set.upload_screenshot(path: screenshot.path, wait_for_processing: wait_for_processing)
            end
          end
        end
      end
      UI.success("Successfully uploaded screenshots to App Store Connect")
    end

    def collect_screenshots(options)
      return [] if options[:skip_screenshots]
      return Loader.load_app_screenshots(options[:screenshots_path], options[:ignore_language_directory_validation])
    end

    # helper method so Spaceship::Tunes.client.available_languages is easier to test
    def self.available_languages
      if Helper.test?
        FastlaneCore::Languages::ALL_LANGUAGES
      else
        Spaceship::Tunes.client.available_languages
      end
    end
  end
end
