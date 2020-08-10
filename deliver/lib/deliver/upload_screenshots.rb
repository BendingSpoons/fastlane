require 'parallel'
require 'spaceship/tunes/tunes'
require 'digest/md5'

require_relative 'app_screenshot'
require_relative 'module'
require_relative 'loader'
require_relative 'utils'

module Deliver
  # upload screenshots to App Store Connect
  class UploadScreenshots
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

      updated_sets_per_language = get_updated_screenshots(localizations, screenshots_per_language)
      checksums_to_delete = get_checksums_to_delete(localizations, updated_sets_per_language)

      delete_screenshots(localizations, checksums_to_delete, max_n_threads)

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

      upload_screenshots(updated_sets_per_language, localizations, options, max_n_threads)
    end

    def get_updated_screenshots(localizations, screenshots_per_language)
      sets_per_language = {} # per locale and device type; all provided screenshots
      updated_sets_per_language = {} # per locale and device type; just the updated screenshots

      # first, divide the new screenshots into sets
      screenshots_per_language.each do |language, screenshots_for_language|
        screenshots_per_device_type = {}

        screenshots_for_language.each do |screenshot|
          display_type = screenshot.device_type

          if display_type.nil?
            UI.error("Error... Screenshot size #{screenshot.screen_size} not valid for App Store Connect")
            next
          end

          bytes = File.binread(screenshot.path)
          checksum = Digest::MD5.hexdigest(bytes)

          screenshots_per_device_type[display_type] ||= []
          screenshots_per_device_type[display_type] << {
              screenshot: screenshot,
              checksum: checksum
          }
        end

        sets_per_language[language] = screenshots_per_device_type
      end

      # remove any duplicate by comparing checksums, keep the first occurrence only
      sets_per_language.values.each do |screenshots_per_device_type|
        screenshots_per_device_type.values.each do |screenshots_with_checksums|
          screenshots_with_checksums.uniq! { |screenshot| screenshot[:checksum] }
        end
      end

      # then, compare the new screenshots with the existing ones
      sets_per_language.each do |language, screenshots_per_device_type|
        updated_screenshots_per_device_type = {}
        localization = localizations.find do |l|
          l.locale == language
        end

        unless localization
          UI.error("Couldn't find localization on version for #{language}")
          next
        end

        app_screenshot_sets_map = {}
        app_screenshot_sets = localization.get_app_screenshot_sets
        app_screenshot_sets.each do |app_screenshot_set|
          app_screenshot_sets_map[app_screenshot_set.screenshot_display_type] = app_screenshot_set
        end

        screenshots_per_device_type.each do |device_type, screenshots_with_checksums|
          existing_screenshots = app_screenshot_sets_map[device_type].app_screenshots
          updated_screenshots_per_device_type[device_type] ||= []

          screenshots_with_checksums.each_with_index do |screenshot_with_checksum, index|
            if index >= 10
              UI.error("Too many screenshots found for device '#{device_type}' in '#{language}', skipping this one (#{screenshot_with_checksum[:screenshot].path})")
              next
            end

            existing_screenshot = existing_screenshots[index]
            next unless existing_screenshot.nil? || existing_screenshot.source_file_checksum != screenshot_with_checksum[:checksum]

            updated_screenshots_per_device_type[device_type] << {
                screenshot: screenshot_with_checksum[:screenshot],
                position: index
            }
          end

          # if there are more existing screenshots, it means some need to be deleted without replacing them
          next unless existing_screenshots.size > screenshots_with_checksums.size

          index = screenshots_with_checksums.size
          while index < screenshots_with_checksums.size
            # add a "nil" screenshot for every position that will no longer be filled (in order to delete them)
            updated_screenshots_per_device_type[device_type] << {
                screenshot: nil,
                position: index
            }
            index += 1
          end
        end

        updated_sets_per_language[language] = updated_screenshots_per_device_type

        count = updated_screenshots_per_device_type.values.reduce(0) { |sum, screenshots_with_positions| sum + screenshots_with_positions.size }
        UI.message("Found #{count} updated screenshots for language #{language}")
      end

      updated_sets_per_language
    end

    def get_checksums_to_delete(localizations, updated_sets_per_language)
      checksums_to_delete = {} # per language and device type

      updated_sets_per_language.each do |language, updated_screenshots_per_device_type|
        checksums_per_device_type = {}
        localization = localizations.find do |l|
          l.locale == language
        end

        unless localization
          UI.error("Couldn't find localization on version for #{language}")
          next
        end

        app_screenshot_sets = localization.get_app_screenshot_sets
        app_screenshot_sets.each do |app_screenshot_set|
          device_type = app_screenshot_set.screenshot_display_type

          unless updated_screenshots_per_device_type.key?(device_type)
            # if there is no device type specified, add empty array of checksums to delete
            checksums_per_device_type[device_type] = {
                checksums: [],
                count_after_delete: app_screenshot_set.app_screenshots.size
            }
            next
          end

          updated_screenshots_set = updated_screenshots_per_device_type[device_type]
          updated_screenshots_positions = updated_screenshots_set.map { |screenshot_with_position| screenshot_with_position[:position] }
          checksums = []

          app_screenshot_set.app_screenshots.each_with_index do |screenshot, index|
            next unless updated_screenshots_positions.include?(index)
            checksums << screenshot.source_file_checksum
          end

          checksums_per_device_type[device_type] = {
              checksums: checksums,
              count_after_delete: app_screenshot_set.app_screenshots.size - checksums.size
          }
        end

        checksums_to_delete[language] = checksums_per_device_type
      end

      checksums_to_delete
    end

    def get_expected_count_after_delete(checksums_to_delete)
      sum = 0

      checksums_to_delete.values.each do |checksums_per_device_type|
        checksums_per_device_type.values.each do |checksums_with_count|
          sum += checksums_with_count[:count_after_delete]
        end
      end

      sum
    end

    def delete_screenshots(localizations, checksums_to_delete, max_n_threads, tries: 5)
      tries -= 1

      # Get localizations on version
      n_threads = [max_n_threads, localizations.length].min
      Parallel.each(localizations, in_threads: n_threads) do |localization|
        # Only delete screenshots if trying to upload
        next unless checksums_to_delete.keys.include?(localization.locale)

        # Find all the screenshots that need to be deleted (via their checksums) and delete them
        screenshot_sets = localization.get_app_screenshot_sets

        # Multi threading delete on single localization
        screenshot_sets.each do |screenshot_set|
          device_type = screenshot_set.screenshot_display_type
          checksums_for_locale = checksums_to_delete[localization.locale]

          # Skip if there are no checksums for the specified locale and device type
          next unless checksums_for_locale.keys.include?(device_type)
          checksums_for_device_type = checksums_for_locale[device_type][:checksums]
          UI.message("Removing #{checksums_for_device_type.size} screenshots for '#{localization.locale}' '#{device_type}'...")

          screenshot_set.app_screenshots.each do |screenshot|
            next unless checksums_for_device_type.include?(screenshot.source_file_checksum)

            UI.verbose("Deleting screenshot - #{localization.locale} #{screenshot_set.screenshot_display_type} #{screenshot.id}")
            Deliver.retry_api_call do
              screenshot.delete!
              UI.verbose("Deleted screenshot - #{localization.locale} #{screenshot_set.screenshot_display_type} #{screenshot.id}")
            end
          end
        end
      end

      # Verify all specified screenshots have been deleted
      # Sometimes API requests will fail but screenshots will still be deleted
      actual_count = count_screenshots(localizations)
      expected_count = get_expected_count_after_delete(checksums_to_delete)
      count = actual_count - expected_count
      UI.important("Number of screenshots not deleted: #{count}")
      if count > 0
        if tries.zero?
          UI.user_error!("Failed verification of all screenshots deleted... #{count} screenshot(s) still exist")
        else
          UI.error("Failed to delete all screenshots... Tries remaining: #{tries}")
          delete_screenshots(localizations, checksums_to_delete, tries: tries)
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

    def upload_screenshots(updated_sets_per_language, localizations, options, max_n_threads)
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

      n_threads = [max_n_threads, updated_sets_per_language.keys.length].min
      Parallel.each(updated_sets_per_language, in_threads: n_threads) do |language, screenshots_per_device_type|
        # Find localization to upload screenshots to
        localization = localizations.find do |l|
          l.locale == language
        end

        unless localization
          UI.error("Couldn't find localization on version for #{language}")
          next
        end

        # Create map to find screenshot set to add screenshot to
        app_screenshot_sets_map = {}
        app_screenshot_sets = localization.get_app_screenshot_sets
        app_screenshot_sets.each do |app_screenshot_set|
          app_screenshot_sets_map[app_screenshot_set.screenshot_display_type] = app_screenshot_set
        end

        screenshots_per_device_type.each do |device_type, screenshots_with_positions|
          UI.message("Uploading #{screenshots_with_positions.length} screenshots for '#{language}', '#{device_type}'")
          screenshots_with_positions.each do |screenshot_with_position|
            screenshot = screenshot_with_position[:screenshot]

            # don't upload the empty screenshots that represent the no-longer filled positions
            next if screenshot.nil?

            position = screenshot_with_position[:position]
            set = app_screenshot_sets_map[device_type]

            unless set
              set = localization.create_app_screenshot_set(attributes: {
                  screenshotDisplayType: device_type
              })
              app_screenshot_sets_map[device_type] = set
            end

            Deliver.retry_api_call do
              UI.message("Uploading '#{screenshot.path}'...")
              set.upload_screenshot(path: screenshot.path, wait_for_processing: wait_for_processing, position: position)
            end
          end
        end
      end
      UI.success("Successfully uploaded screenshots to App Store Connect")
    end

    def collect_screenshots(options)
      return [] if options[:skip_screenshots]
      return collect_screenshots_for_languages(options[:screenshots_path], options[:ignore_language_directory_validation])
    end

    def collect_screenshots_for_languages(path, ignore_validation)
      screenshots = []
      extensions = '{png,jpg,jpeg}'

      available_languages = UploadScreenshots.available_languages.each_with_object({}) do |lang, lang_hash|
        lang_hash[lang.downcase] = lang
      end

      Loader.language_folders(path, ignore_validation).each do |lng_folder|
        language = File.basename(lng_folder)

        # Check to see if we need to traverse multiple platforms or just a single platform
        if language == Loader::APPLE_TV_DIR_NAME || language == Loader::IMESSAGE_DIR_NAME
          screenshots.concat(collect_screenshots_for_languages(File.join(path, language), ignore_validation))
          next
        end

        files = Dir.glob(File.join(lng_folder, "*.#{extensions}"), File::FNM_CASEFOLD).sort
        next if files.count == 0

        framed_screenshots_found = Dir.glob(File.join(lng_folder, "*_framed.#{extensions}"), File::FNM_CASEFOLD).count > 0

        UI.important("Framed screenshots are detected! 🖼 Non-framed screenshot files may be skipped. 🏃") if framed_screenshots_found

        language_dir_name = File.basename(lng_folder)

        if available_languages[language_dir_name.downcase].nil?
          UI.user_error!("#{language_dir_name} is not an available language. Please verify that your language codes are available in iTunesConnect. See https://developer.apple.com/library/content/documentation/LanguagesUtilities/Conceptual/iTunesConnect_Guide/Chapters/AppStoreTerritories.html for more information.")
        end

        language = available_languages[language_dir_name.downcase]

        files.each do |file_path|
          is_framed = file_path.downcase.include?("_framed.")
          is_watch = file_path.downcase.include?("watch")

          if framed_screenshots_found && !is_framed && !is_watch
            UI.important("🏃 Skipping screenshot file: #{file_path}")
            next
          end

          screenshots << AppScreenshot.new(file_path, language)
        end
      end

      # Checking if the device type exists in spaceship
      # Ex: iPhone 6.1 inch isn't supported in App Store Connect but need
      # to have it in there for frameit support
      unaccepted_device_shown = false
      screenshots.select! do |screenshot|
        exists = !screenshot.device_type.nil?
        unless exists
          UI.important("Unaccepted device screenshots are detected! 🚫 Screenshot file will be skipped. 🏃") unless unaccepted_device_shown
          unaccepted_device_shown = true

          UI.important("🏃 Skipping screenshot file: #{screenshot.path} - Not an accepted App Store Connect device...")
        end
        exists
      end

      return screenshots
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
