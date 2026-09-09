# frozen_string_literal: true

require "test_helper"

# Whether this machine has a browser to hand a URL to. Both answers are said before anything is
# served, because a console nobody can open is a port for nothing.
class BrowserTest < Minitest::Test
  def headless(env, platform) = Pinecall::UI::Browser.headless(env:, platform:)

  def test_a_laptop_with_a_screen_can_open_one
    assert_nil headless({}, :darwin)
    assert_nil headless({ "DISPLAY" => ":0" }, :linux)
    assert_nil headless({ "WAYLAND_DISPLAY" => "wayland-0" }, :linux)
  end

  def test_over_ssh_there_is_no_screen_on_this_end_and_it_says_so
    assert_includes headless({ "SSH_CONNECTION" => "10.0.0.1 22" }, :darwin), "ssh"
  end

  def test_a_linux_with_no_display_has_no_browser_to_hand_it_to
    assert_includes headless({}, :linux), "DISPLAY"
  end
end
