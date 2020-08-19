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
      candidate_screenshots_per_language = screenshots.group_by(&:language)

      localizations = version.get_app_store_version_localizations

      app_store_screenshot_sets_map = load_app_store_screenshot_sets(localizations)

      changed_sets_per_language = get_changed_screenshots(app_store_screenshot_sets_map, candidate_screenshots_per_language)
      app_store_screenshots_to_delete = get_app_store_screenshots_to_delete(app_store_screenshot_sets_map, changed_sets_per_language)

      delete_screenshots(localizations, app_store_screenshot_sets_map, app_store_screenshots_to_delete, max_n_threads)

      # Finding languages to enable
      languages = candidate_screenshots_per_language.keys
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

      upload_screenshots(changed_sets_per_language, localizations, options, max_n_threads)
    end

    def load_app_store_screenshot_sets(localizations)
      app_store_screenshot_sets_map = {}

      localizations.each do |localization|
        app_store_sets_for_language = {}
        app_store_screenshot_sets = localization.get_app_screenshot_sets
        app_store_screenshot_sets.each do |app_store_screenshot_set|
          app_store_sets_for_language[app_store_screenshot_set.screenshot_display_type] = app_store_screenshot_set
        end

        app_store_screenshot_sets_map[localization.locale] = app_store_sets_for_language
      end

      app_store_screenshot_sets_map
    end

    def get_changed_screenshots(app_store_screenshot_sets_map, candidate_screenshots_per_language)
      candidate_sets_per_language = {} # per locale and device type; all provided screenshots
      changed_sets_per_language = {} # per locale and device type; screenshots that have been added, removed or updated

      # first, divide the new screenshots into sets
      candidate_screenshots_per_language.each do |language, candidates_for_language|
        candidates_per_device_type = {}

        candidates_for_language.each do |candidate_screenshot|
          display_type = candidate_screenshot.device_type

          if display_type.nil?
            UI.error("Error... Screenshot size #{candidate_screenshot.screen_size} not valid for App Store Connect")
            next
          end

          bytes = File.binread(candidate_screenshot.path)
          checksum = Digest::MD5.hexdigest(bytes)

          candidates_per_device_type[display_type] ||= []
          candidates_per_device_type[display_type] << {
              screenshot: candidate_screenshot,
              checksum: checksum
          }
        end

        candidate_sets_per_language[language] = candidates_per_device_type
      end

      # remove any duplicate by comparing checksums, keep the first occurrence only
      candidate_sets_per_language.values.each do |candidate_sets_per_device_type|
        candidate_sets_per_device_type.values.each do |candidates_with_checksums|
          candidates_with_checksums.uniq! { |screenshot| screenshot[:checksum] }
        end
      end

      # then, compare the new screenshots with the existing ones
      candidate_sets_per_language.each do |language, candidate_sets_per_device_type|
        changed_screenshots_per_device_type = {}

        unless app_store_screenshot_sets_map.key?(language)
          UI.error("Couldn't find localization on version for #{language}")
          next
        end

        app_store_sets_per_device_type = app_store_screenshot_sets_map[language]
        candidate_sets_per_device_type.each do |device_type, candidates_with_checksums|
          app_store_screenshots = app_store_sets_per_device_type[device_type].app_screenshots
          changed_screenshots_per_device_type[device_type] ||= []

          candidates_with_checksums.each_with_index do |candidate_with_checksum, index|
            if index >= 10
              UI.error("Too many screenshots found for device '#{device_type}' in '#{language}', skipping this one (#{candidate_with_checksum[:screenshot].path})")
              next
            end

            app_store_screenshot = app_store_screenshots[index]
            next unless app_store_screenshot.nil? || app_store_screenshot.source_file_checksum != candidate_with_checksum[:checksum]

            # the added and updated screenshots from the candidates
            changed_screenshots_per_device_type[device_type] << {
                screenshot: candidate_with_checksum[:screenshot],
                position: index
            }
          end

          # if there are more (existing) app store screenshots, it means some need to be removed without being replaced
          next unless app_store_screenshots.size > candidates_with_checksums.size

          index = candidates_with_checksums.size
          while index < app_store_screenshots.size
            # add a "nil" screenshot for every position that will no longer be filled (in order to delete them)
            changed_screenshots_per_device_type[device_type] << {
                screenshot: nil,
                position: index
            }
            index += 1
          end
        end

        changed_sets_per_language[language] = changed_screenshots_per_device_type

        count = changed_screenshots_per_device_type.values.reduce(0) { |sum, screenshots_with_positions| sum + screenshots_with_positions.size }
        UI.message("Found #{count} added, removed or updated screenshots for language #{language}")
      end

      changed_sets_per_language
    end

    def get_app_store_screenshots_to_delete(app_store_screenshot_sets_map, changed_sets_per_language)
      screenshots_to_delete = {} # per language and device type

      changed_sets_per_language.each do |language, changed_sets_per_device_type|
        screenshots_to_delete_per_device_type = {}
        app_store_sets_per_device_type = app_store_screenshot_sets_map[language]

        app_store_sets_per_device_type.values.each do |app_store_screenshot_set|
          device_type = app_store_screenshot_set.screenshot_display_type

          unless changed_sets_per_device_type.key?(device_type)
            # if there is no device type specified, add empty array of screenshots to delete
            screenshots_to_delete_per_device_type[device_type] = {
                screenshots: [],
                count_after_delete: app_store_screenshot_set.app_screenshots.size
            }
            next
          end

          changed_screenshot_set = changed_sets_per_device_type[device_type]
          changed_screenshot_positions = changed_screenshot_set.map { |screenshot_with_position| screenshot_with_position[:position] }
          screenshots_to_delete_for_device_type = []

          app_store_screenshot_set.app_screenshots.each_with_index do |screenshot, index|
            next unless changed_screenshot_positions.include?(index)
            screenshots_to_delete_for_device_type << screenshot
          end

          screenshots_to_delete_per_device_type[device_type] = {
              screenshots: screenshots_to_delete_for_device_type,
              count_after_delete: app_store_screenshot_set.app_screenshots.size - screenshots_to_delete_for_device_type.size
          }
        end

        screenshots_to_delete[language] = screenshots_to_delete_per_device_type
      end

      screenshots_to_delete
    end

    def get_expected_count_after_delete(app_store_screenshots_to_delete)
      sum = 0

      app_store_screenshots_to_delete.values.each do |screenshots_per_device_type|
        screenshots_per_device_type.values.each do |screenshot_with_count|
          sum += screenshot_with_count[:count_after_delete]
        end
      end

      sum
    end

    def delete_screenshots(localizations, app_store_screenshot_sets_map, app_store_screenshots_to_delete, max_n_threads, tries: 5)
      tries -= 1

      # Get localizations on version
      n_threads = [max_n_threads, localizations.length].min
      Parallel.each(localizations, in_threads: n_threads) do |localization|
        language = localization.locale

        next unless app_store_screenshots_to_delete.key?(language)

        # Find all the screenshots that need to be deleted (via their ID) and delete them
        app_store_sets_per_device_type = app_store_screenshot_sets_map[language]

        # Multi threading delete on single localization
        app_store_sets_per_device_type.values.each do |app_store_screenshot_set|
          device_type = app_store_screenshot_set.screenshot_display_type
          screenshots_to_delete_per_device_type = app_store_screenshots_to_delete[language]

          # Skip if there are no specified screenshots to delete for the given locale and device type
          next unless screenshots_to_delete_per_device_type.key?(device_type)
          screenshots_to_delete_for_device_type = screenshots_to_delete_per_device_type[device_type][:screenshots]
          UI.message("Removing #{screenshots_to_delete_for_device_type.size} screenshots for '#{language}' '#{device_type}'...")

          ids_to_delete = screenshots_to_delete_for_device_type.map(&:id)

          app_store_screenshot_set.app_screenshots.each do |app_store_screenshot|
            next unless ids_to_delete.include?(app_store_screenshot.id)

            UI.message("Deleting screenshot - #{language} #{app_store_screenshot_set.screenshot_display_type} #{app_store_screenshot.id}")
            Deliver.retry_api_call do
              app_store_screenshot.delete!
              UI.message("Deleted screenshot - #{language} #{app_store_screenshot_set.screenshot_display_type} #{app_store_screenshot.id}")
            end
          end
        end
      end

      # Verify all specified screenshots have been deleted
      # Sometimes API requests will fail but screenshots will still be deleted
      # Also, need to reload the sets to get the actual screenshots in App Store after the deletion
      reloaded_app_store_sets_map = load_app_store_screenshot_sets(localizations)
      actual_count = count_screenshots(reloaded_app_store_sets_map, app_store_screenshots_to_delete)
      expected_count = get_expected_count_after_delete(app_store_screenshots_to_delete)
      count = actual_count - expected_count
      UI.important("Number of screenshots not deleted: #{count}")
      if count > 0
        if tries.zero?
          UI.user_error!("Failed verification of all screenshots deleted... #{count} screenshot(s) still exist")
        else
          UI.error("Failed to delete all screenshots... Tries remaining: #{tries}")
          delete_screenshots(localizations, reloaded_app_store_sets_map, app_store_screenshots_to_delete, max_n_threads, tries: tries)
        end
      else
        UI.message("Successfully deleted all screenshots")
      end
    end

    def count_screenshots(app_store_screenshot_sets_map, app_store_screenshots_to_delete)
      count = 0

      app_store_screenshot_sets_map.each do |language, app_store_sets_for_language|
        # disregard count for language if nothing is deleted in it
        next unless app_store_screenshots_to_delete.key?(language)

        app_store_sets_for_language.values.each do |app_store_set_for_device_type|
          count += app_store_set_for_device_type.app_screenshots.size
        end
      end

      count
    end

    def upload_screenshots(changed_sets_per_language, localizations, options, max_n_threads)
      # Check if should wait for processing
      # Default to waiting if submitting for review (since needed for submission)
      # Otherwise use environment variable
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

      # need to reload the sets after the delete operations
      app_store_screenshot_sets_map = load_app_store_screenshot_sets(localizations)

      n_threads = [max_n_threads, changed_sets_per_language.keys.length].min
      Parallel.each(changed_sets_per_language, in_threads: n_threads) do |language, changed_sets_per_device_type|
        # Find localization to upload screenshots to
        localization = localizations.find do |l|
          l.locale == language
        end

        unless localization
          UI.error("Couldn't find localization on version for #{language}")
          next
        end

        app_store_sets_for_language = app_store_screenshot_sets_map[language]

        changed_sets_per_device_type.each do |device_type, changed_screenshots_for_device_type|
          changed_screenshots_to_be_uploaded = changed_screenshots_for_device_type.reject { |screenshot_with_position| screenshot_with_position[:screenshot].nil? }
          UI.message("Uploading #{changed_screenshots_to_be_uploaded.length} screenshots for '#{language}', '#{device_type}'")

          changed_screenshots_to_be_uploaded.each do |changed_screenshot_with_position|
            changed_screenshot = changed_screenshot_with_position[:screenshot]

            # don't upload the empty screenshots that represent the no-longer filled positions
            next if changed_screenshot.nil?

            position = changed_screenshot_with_position[:position]
            app_store_screenshot_set = app_store_sets_for_language[device_type]

            unless app_store_screenshot_set
              app_store_screenshot_set = localization.create_app_screenshot_set(attributes: {
                  screenshotDisplayType: device_type
              })
              app_store_sets_for_language[device_type] = app_store_screenshot_set
            end

            Deliver.retry_api_call do
              UI.message("Uploading '#{changed_screenshot.path}'...")
              app_store_screenshot_set.upload_screenshot(path: changed_screenshot.path, wait_for_processing: wait_for_processing, position: position)
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
