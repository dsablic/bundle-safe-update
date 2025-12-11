# frozen_string_literal: true

module BundleSafeUpdate
  module ColorOutput
    COLORS = {
      green: "\e[32m",
      yellow: "\e[33m",
      red: "\e[31m",
      cyan: "\e[36m",
      reset: "\e[0m"
    }.freeze

    def colorize(text, color)
      return text unless tty?

      "#{COLORS[color]}#{text}#{COLORS[:reset]}"
    end

    def green(text)
      colorize(text, :green)
    end

    def yellow(text)
      colorize(text, :yellow)
    end

    def red(text)
      colorize(text, :red)
    end

    def cyan(text)
      colorize(text, :cyan)
    end

    private

    def tty?
      $stdout.tty?
    end
  end
end
