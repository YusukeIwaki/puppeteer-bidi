# frozen_string_literal: true

require 'chunky_png'
require 'base64'

module GoldenComparator
  # Compare a screenshot (base64 string) with a golden image
  # @param screenshot_base64 [String] Base64-encoded PNG data
  # @param golden_filename [String] Filename of the golden image
  # @param max_diff_pixels [Integer] Maximum number of pixels allowed to differ
  # @param pixel_threshold [Integer] Maximum color difference per channel (0-255)
  # @return [Boolean] True if images match within tolerance
  def compare_with_golden(screenshot_base64, golden_filename, max_diff_pixels: 0, pixel_threshold: 1)
    golden_path = File.join(__dir__, '../golden-firefox', golden_filename)

    unless File.exist?(golden_path)
      raise "Golden image not found: #{golden_path}"
    end

    # Decode the screenshot
    screenshot_data = Base64.decode64(screenshot_base64)
    screenshot_image = ChunkyPNG::Image.from_blob(screenshot_data)

    # Load the golden image
    golden_image = ChunkyPNG::Image.from_file(golden_path)

    # Compare dimensions
    return false if screenshot_image.width != golden_image.width
    return false if screenshot_image.height != golden_image.height

    # Compare pixel by pixel with threshold
    diff_pixels = 0
    (0...screenshot_image.height).each do |y|
      (0...screenshot_image.width).each do |x|
        golden_pixel = golden_image[x, y]
        actual_pixel = screenshot_image[x, y]

        if golden_pixel != actual_pixel
          # Check if difference is within threshold
          unless pixels_similar?(golden_pixel, actual_pixel, pixel_threshold)
            diff_pixels += 1
            return false if diff_pixels > max_diff_pixels
          end
        end
      end
    end

    true
  end

  private

  # Check if two pixels are similar within a threshold
  def pixels_similar?(pixel1, pixel2, threshold)
    r1 = ChunkyPNG::Color.r(pixel1)
    g1 = ChunkyPNG::Color.g(pixel1)
    b1 = ChunkyPNG::Color.b(pixel1)
    a1 = ChunkyPNG::Color.a(pixel1)

    r2 = ChunkyPNG::Color.r(pixel2)
    g2 = ChunkyPNG::Color.g(pixel2)
    b2 = ChunkyPNG::Color.b(pixel2)
    a2 = ChunkyPNG::Color.a(pixel2)

    (r1 - r2).abs <= threshold &&
      (g1 - g2).abs <= threshold &&
      (b1 - b2).abs <= threshold &&
      (a1 - a2).abs <= threshold
  end

  # Save a screenshot for debugging
  # @param screenshot_base64 [String] Base64-encoded PNG data
  # @param filename [String] Filename to save to
  def save_screenshot(screenshot_base64, filename)
    output_dir = File.join(__dir__, '../output')
    FileUtils.mkdir_p(output_dir)

    output_path = File.join(output_dir, filename)
    screenshot_data = Base64.decode64(screenshot_base64)
    File.binwrite(output_path, screenshot_data)

    output_path
  end
end
