# frozen_string_literal: true

require_relative "os"
require_relative "browser_helpers"

module Capybara
  module Screenshot
    class Screenshoter
      attr_reader :capture_options, :comparison_options, :driver

      def initialize(capture_options, driver)
        @capture_options = capture_options
        @comparison_options = comparison_options
        @driver = driver
      end

      def crop
        @capture_options[:crop]
      end

      def wait
        @capture_options[:wait]
      end

      def self.attempts_screenshot_paths(base_file)
        Dir["#{base_file.to_s.chomp(".png")}.attempt_*.png"].sort
      end

      def self.cleanup_attempts_screenshots(base_file)
        FileUtils.rm_rf attempts_screenshot_paths(base_file)
      end

      # Try to get screenshot from browser.
      # On `stability_time_limit` it checks that page stop updating by comparison several screenshot attempts
      # On reaching `wait` limit then it has been failed. On failing we annotate screenshot attempts to help to debug
      def take_comparison_screenshot(screenshot_path)
        new_screenshot_path = Screenshoter.gen_next_attempt_path(screenshot_path, 0)

        take_screenshot(new_screenshot_path)

        FileUtils.mv(new_screenshot_path, screenshot_path, force: true)
        Screenshoter.cleanup_attempts_screenshots(screenshot_path)
      end

      def self.gen_next_attempt_path(screenshot_path, iteration)
        Pathname.new(screenshot_path).sub_ext(format(".attempt_%02i.png", iteration))
      end

      def take_screenshot(screenshot_path)
        blurred_input = prepare_page_for_screenshot(timeout: wait)

        # Take browser screenshot and save
        browser_save_screenshot(screenshot_path)

        # Load saved screenshot and pre-process it
        process_screenshot(screenshot_path)
      ensure
        blurred_input&.click
      end

      def browser_save_screenshot(screenshot_path)
        BrowserHelpers.session.save_screenshot(screenshot_path)
      end

      def process_screenshot(screenshot_path)
        # TODO(uwe): Remove when chromedriver takes right size screenshots
        # TODO: Adds tests when this case is true
        if selenium_with_retina_screen?
          reduce_retina_image_size(screenshot_path)
        end
        # ODOT

        if crop
          image = driver.from_file(screenshot_path)
          cropped_image = driver.crop(crop, image)
          driver.save_image_to(cropped_image, screenshot_path)
        end
      end

      def reduce_retina_image_size(file_name)
        expected_image_width = Screenshot.window_size[0]
        saved_image = driver.from_file(file_name.to_s)
        return if driver.width_for(saved_image) < expected_image_width * 2

        notice_how_to_avoid_this

        new_height = expected_image_width * driver.height_for(saved_image) / driver.width_for(saved_image)
        resized_image = driver.resize_image_to(saved_image, expected_image_width, new_height)

        driver.save_image_to(resized_image, file_name)
      end

      def notice_how_to_avoid_this
        unless defined?(@_csd_retina_warned)
          warn "Halving retina screenshot.  " \
                'You should add "force-device-scale-factor=1" to your Chrome chromeOptions args.'
          @_csd_retina_warned = true
        end
      end

      def prepare_page_for_screenshot(timeout:)
        wait_images_loaded(timeout: timeout)

        blurred_input = if Screenshot.blur_active_element
          BrowserHelpers.blur_from_focused_element
        end

        if Screenshot.hide_caret
          BrowserHelpers.hide_caret
        end

        blurred_input
      end

      def wait_images_loaded(timeout:)
        start = Time.now
        loop do
          pending_image = BrowserHelpers.pending_image_to_load
          break unless pending_image

          assert(
            (Time.now - start) < timeout,
            "Images not loaded after #{timeout}s: #{pending_image.inspect}"
          )

          sleep 0.025
        end
      end

      private

      def selenium_with_retina_screen?
        Os::ON_MAC && BrowserHelpers.selenium? && Screenshot.window_size
      end
    end
  end
end
