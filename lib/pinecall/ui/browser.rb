# frozen_string_literal: true

module Pinecall
  module UI
    # Detects whether a local browser is usable and opens URLs in it.
    module Browser
      # Unknown platforms fall back to xdg-open.
      OPENERS = { darwin: "open", windows: "start", linux: "xdg-open" }.freeze

      module_function

      # The reason no local browser is usable (ssh session, Linux without a display), or nil.
      # The Talk screen needs a local microphone.
      def headless(env: ENV, platform: this_platform)
        return "this is an ssh session" if env["SSH_CONNECTION"]
        return nil unless platform == :linux
        return nil if env["DISPLAY"] || env["WAYLAND_DISPLAY"]

        "no DISPLAY and no WAYLAND_DISPLAY"
      end

      # Open `url` without waiting; failures are ignored since the URL is also printed.
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
