module Color
  # colorization
  def self.colorize(str, color_code)
    "\e[#{color_code}m#{str}\e[0m"
  end

  def self.red(str)
    colorize(str, 31)
  end

  def self.green(str)
    colorize(str, 32)
  end

  def self.yellow(str)
    colorize(str, 33)
  end

  def self.blue(str)
    colorize(str, 34)
  end

  def self.pink(str)
    colorize(str, 35)
  end

  def self.light_blue(str)
    colorize(str, 36)
  end
end