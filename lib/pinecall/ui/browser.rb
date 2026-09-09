# frozen_string_literal: true

module Pinecall
  module UI
    # This machine's browser: whether it has one to speak of, and how a URL is handed to it.
    module Browser
      # One command per platform. Anything else is treated as a Linux with xdg-open, which is
      # what a BSD or a container with a desktop most likely has.
      OPENERS = { darwin: "open", windows: "start", linux: "xdg-open" }.freeze

      module_function

      # Why no page can open here, or nil when one can.
      #
      # The Talk screen needs a microphone, and a microphone is a browser's on a screen: over ssh
      # there is no screen on this end, and a Linux with no display has no browser to hand a URL
      # to. Both are said before anything is served.
      def headless(env: ENV, platform: this_platform)
        return "this is an ssh session" if env["SSH_CONNECTION"]
        return nil unless platform == :linux
        return nil if env["DISPLAY"] || env["WAYLAND_DISPLAY"]

        "no DISPLAY and no WAYLAND_DISPLAY"
      end

      # Hand this URL to the browser and never wait for it: the URL is on screen either way.
      def open(url, platform: this_platform)
        opener = OPENERS.fetch(platform, OPENERS[:linux])
        pid = Process.spawn(opener, url, out: File::NULL, err: File::NULL)
        Process.detach(pid)
        nil
      rescue Errno::ENOENT, SystemCallError
        nil
      end

      def this_platform
        case RbConfig::CONFIG["host_os"]
        when /darwin/ then :darwin
        when /mswin|mingw|cygwin/ then :windows
        else :linux
        end
      end
    end
  end
end
