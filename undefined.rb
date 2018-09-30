require 'matrix'

module Color
  class Illuminant < Struct.new(:refx, :refy, :refz, :linear_rgb_coefficients)
    def rgb_components(x, y, z)
      (linear_rgb_coefficients * Matrix[[x], [y], [z]]).column(0)
    end
  end

  # Reference values obtained from http://www.easyrgb.com/en/math.php and from
  # https://en.wikipedia.org/wiki/SRGB.
  D65_2 = Illuminant.new(
    95.047, 100.0, 108.883,
    Matrix[
      [ 3.2406, -1.5372, -0.4986],
      [-0.9689,  1.8758,  0.0415],
      [ 0.0557, -0.2040,  1.0570],
    ].freeze
  ).freeze

  class Luv
    include Enumerable

    attr_reader :l, :u, :v

    def initialize(l, u, v, illuminant: D65_2)
      @l, @u, @v = l, u, v
      @illuminant = illuminant
    end

    def each(&b)
      [@l, @u, @v].each(&b)
    end

    def blend(other, weight)
      weight = [0.0, [1.0, weight].min].max
      selfweight = 1.0 - weight
      self.class.new(@l * selfweight + other.l * weight,
                     @u * selfweight + other.u * weight,
                     @v * selfweight + other.v * weight)
    end

    def reflect_l(dark, light)
      # dark_du = @u - dark.u
      # dark_dv = @v - dark.v
      # light_du = @u - light.u
      # light_dv = @v - light.v
      # dl = light.l - dark.l
      # l = (light.l**2 + light_du**2 + light_dv**2 - dark.l**2 - dark_du**2 - dark_dv**2)/2.0/dl
      # self.class.new(l, @u, @v)
      self.class.new(light.l - @l + dark.l, @u, @v)
    end

    def srgb
      @srgb ||= xyz.srgb.cap
    end

    def to_s
      srgb.to_s
    end

    def xyz
      return @xyz if @xyz
      # Code adapted from http://www.easyrgb.com/en/math.php.
      vary = (@l + 16)/116.0
      if vary**3 > 0.008856
        vary = vary**3
      else
        vary = (vary - 16/116.0)/7.787
      end
      refu = (4 * @illuminant.refx)/(@illuminant.refx + (15 * @illuminant.refy) + (3 * @illuminant.refz))
      refv = (9 * @illuminant.refy)/(@illuminant.refx + (15 * @illuminant.refy) + (3 * @illuminant.refz))
      varu = @u/(13.0 * @l) + refu
      varv = @v/(13.0 * @l) + refv
      y = vary * 100
      x = - (9 * y * varu)/((varu - 4) * varv - varu * varv)
      z = (9 * y - (15 * varv * y) - (varv * x ))/(3 * varv)
      @xyz = Xyz.new(x, y, z, illuminant: @illuminant)
    end

    def contrast_ratio(other)
      l2, l1 = [relative_luminance, other.relative_luminance].sort
      (l1 + 0.05) / (l2 + 0.05)
    end

    def relative_luminance
      @relative_luminance ||= xyz.rgb.relative_luminance
    end
  end

  class Xyz
    include Enumerable

    def initialize(x, y, z, illuminant: D65_2)
      @x, @y, @z = x, y, z
      @illuminant = illuminant
    end

    def each(&b)
      [@x, @y, @z].each(&b)
    end

    def srgb
      @srgb ||= rgb.srgb
    end

    def rgb
      @rgb ||= Rgb.new(*@illuminant.rgb_components(*map { |c| c/100.0 }))
    end
  end

  class Rgb
    include Enumerable

    def initialize(r, g, b, illuminant: D65_2)
      @r, @g, @b = r, g, b
      @illuminant = illuminant
    end

    def each(&b)
      [@r, @g, @b].each(&b)
    end

    def relative_luminance
      @relative_luminance ||= 0.2126*@r + 0.7152*@g + 0.0722*@b
    end

    def srgb
      raise 'cannot convert to sRGB: not D65/2º' unless @illuminant.equal?(D65_2)
      @srgb ||= SRgb.new(
        *map { |c| (c > 0.0031308 ? 1.055 * (c**(1/2.4)) - 0.055 : 12.92 * c) * 255 }
      )
    end
  end

  class SRgb
    include Enumerable

    def initialize(r, g, b)
      @r, @g, @b = r, g, b
    end

    def each(&b)
      [@r, @g, @b].each(&b)
    end

    def cap
      self.class.new(*map { |c| [0.0, [255.0, c].min].max })
    end

    def hex
      @hex ||= format("#%02x%02x%02x", *cap.map(&:round))
    end

    alias to_s hex
  end
end

class Palette
  include Enumerable

  def add(name, color, meta = {})
    tone = Tone.new(color, meta)
    (@palette ||= {}).merge!(name.to_sym => tone)
    define_singleton_method(name) { tone }
  end

  def get_color(name)
    (@palette ||= {}).fetch(name.to_sym)
  end

  def each(&block)
    (@palette ||= {}).each(&block)
  end

  class Tone < SimpleDelegator
    def initialize(color, background: false, foreground: false, accent: false, alternate: false)
      @background = background
      @foreground = foreground
      @accent = accent
      @alternate = alternate
      super(color)
    end

    def background?
      @background
    end

    def foreground?
      @foreground
    end

    def accent?
      @accent
    end

    def alternate?
      @alternate
    end
  end
end

class Scheme
  def initialize(bg, fg, **colors)
    @bg = bg
    @fg = fg
    @colors = colors
  end

  def dark
    return @dark if @dark
    dark = Palette.new
    dark.add(:bg, @bg, background: true)
    dark.add(:fg, @fg, foreground: true)
    @colors.each do |name, color|
      dark.add(:"#{name}0", color, accent: true)
      dark.add(:"#{name}1", color.blend(@bg, 0.25), accent: true)
      dark.add(:"#{name}2", color.blend(@bg, 0.75), background: true)
    end
    grayscale do |weight, meta, index|
      dark.add(:"gray#{index}", @bg.blend(@fg, weight), meta)
    end
    @dark = dark
  end

  def light
    return @light if @light
    light = Palette.new
    light.add(:bg, @fg, background: true)
    light.add(:fg, @bg, foreground: true)
    @colors.keys.each do |name|
      color = dark.get_color(:"#{name}0").reflect_l(@bg, @fg)
      light.add(:"#{name}0", color, accent: true)
      light.add(:"#{name}1", color.blend(@fg, 0.25), accent: true)
      light.add(:"#{name}2", color.blend(@fg, 0.75), background: true)
    end
    grayscale do |weight, meta, index|
      light.add(:"gray#{index}", @fg.blend(@bg, weight), meta)
    end
    @light = light
  end

private

  def grayscale(&block)
    [
      [0.05, { alternate: true, background: true }],
      [0.1, {}],
      [0.25, {}],
      [0.38, {}],
      [0.5, { accent: true }]
    ].each_with_index do |(weight, meta), index|
      yield weight, meta, index
    end
  end
end

Undefined = Scheme.new(
  black = Color::Luv.new(13, 3, 5),
  white = Color::Luv.new(78, 21, 31),
  red: Color::Luv.new(52, 128, 18),
  lime: Color::Luv.new(60, 5, 66),
  yellow: Color::Luv.new(65, 50, 45),
  purple: Color::Luv.new(50, 84, -5),
  orange: Color::Luv.new(57, 103, 39),
  cyan: Color::Luv.new(60, -30, 1),
)

if $stdout.tty?
  Undefined.dark.zip(Undefined.light).each do |(_, dark, _), (_, light, _)|
    puts([[dark, black, white], [light, white, black]].map do |color, bgcolor, fgcolor|
      br, bg, bb = bgcolor.srgb.map(&:round)
      fr, fg, fb = fgcolor.srgb.map(&:round)
      rgb = color.xyz.srgb
      cr, cg, cb = rgb.cap.map(&:round)
      f = format("% 4d,% 4d,% 4d", *rgb.map(&:round))
      c = format("%0.2f:1", bgcolor.contrast_ratio(color))
      "#{f} (#{c}):\x1b[38;2;#{cr};#{cg};#{cb}m\x1b[48;2;#{br};#{bg};#{bb}m#{rgb.hex}\x1b[0m" +
        "\x1b[48;2;#{cr};#{cg};#{cb}m\x1b[38;2;#{fr};#{fg};#{fb}m#{rgb.hex}\x1b[0m"
    end.join)
  end
end
