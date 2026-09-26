# frozen_string_literal: true

require "test_helper"

# The vendored console build is present and complete.
class ConsoleTest < Minitest::Test
  FILES = Pinecall::UI::FILES

  def test_the_compiled_console_ships_with_the_gem
    assert File.directory?(FILES), "console/ is missing: run `rake console:build`"
    assert_path_exists File.join(FILES, "index.html")
  end

  def test_every_asset_the_page_names_is_a_file_that_is_here
    page = File.read(File.join(FILES, "index.html"))
    named = page.scan(%r{(?:src|href)="\.?/?(assets/[^"]+)"}).flatten

    refute_empty named, "the page names no assets at all"
    named.each { |asset| assert_path_exists File.join(FILES, asset) }
  end

  def test_it_says_where_it_came_from_and_how_to_make_it_again
    said = File.read(File.join(FILES, "README.md"))

    assert_includes said, "generated"
    assert_includes said, "rake console:build"
  end

  def test_the_page_addresses_its_assets_from_the_base_and_not_from_the_root
    page = File.read(File.join(FILES, "index.html"))

    # Root-absolute asset paths would miss the nonce prefix and get index.html back.
    refute_match(%r{(?:src|href)="/assets/}, page)
  end

  def test_the_bundle_carries_no_key_and_no_key_s_name
    Dir[File.join(FILES, "assets", "*")].each do |asset|
      body = File.binread(asset)

      refute_match(/PINECALL_(API|DEV)_KEY/, body)
      refute_match(/pk_[A-Za-z0-9]{8}/, body)
    end
  end
end
