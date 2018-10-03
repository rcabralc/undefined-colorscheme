require 'matrix'

module Color
  class Illuminant < Struct.new(:refxyz, :white_point)
    def refx
      refxyz[0]
    end

    def refy
      refxyz[1]
    end

    def refz
      refxyz[2]
    end

    # Conversion methods adapted from
    # http://www.ryanjuckett.com/programming/rgb-color-space-conversion/

    def XYZ2RGB_matrix(rgb_primaries)
      RGB2XYZ_matrix(rgb_primaries).inverse
    end

    def RGB2XYZ_matrix(rgb_primaries)
      rxyz = xyz_complete(rgb_primaries.r)
      gxyz = xyz_complete(rgb_primaries.g)
      bxyz = xyz_complete(rgb_primaries.b)
      wXYZ = xyz_complete(white_point) / white_point[1]
      rgbxyz = Matrix.columns([rxyz, gxyz, bxyz])
      scale = rgbxyz.inverse * wXYZ
      rgbxyz * Matrix[[scale[0], 0, 0], [0, scale[1], 0], [0, 0, scale[2]]]
    end

  private

    def xyz_complete(c)
      Vector[c[0], c[1], 1 - c[0] - c[1]]
    end
  end

  # Reference values obtained from http://www.easyrgb.com/en/math.php and from
  # http://www.ryanjuckett.com/programming/rgb-color-space-conversion/
  D65_2 = Illuminant.new([95.047, 100.0, 108.883], [0.3127, 0.3290]).freeze

  class CIELUV
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
      self.class.new(*zip(other).map { |(c1, c2)| c1 * selfweight + c2 * weight })
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
      @srgb ||= linear_srgb.srgb
    end

    def contrast_ratio(other)
      [relative_luminance, other.relative_luminance]
        .sort.reverse.map { |y| y + 0.05 }.reduce(&:/)
    end

    def relative_luminance
      xyz.y/100.0
    end

  private

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
      @xyz = CIEXYZ.new(x, y, z)
    end

    def linear_srgb
      @linear_srgb ||= LinearSRGB.new(*(
        @illuminant.XYZ2RGB_matrix(LinearSRGB.primaries) *
        Vector[*xyz.map { |c| c/100.0 }]
      ))
    end
  end

  class CIEXYZ < Struct.new(:x, :y, :z)
    include Enumerable

    def initialize(*a)
      super
      freeze
    end

    def each(&b)
      [x, y, z].each(&b)
    end
  end

  class LinearSRGB
    include Enumerable

    class << self; attr_reader :primaries; end
    @primaries = Struct.new(:r, :g, :b).new(
      Vector[0.64, 0.33],
      Vector[0.30, 0.60],
      Vector[0.15, 0.06]
    ).freeze

    def initialize(r, g, b)
      @r, @g, @b = r, g, b
    end

    def each(&b)
      [@r, @g, @b].each(&b)
    end

    def srgb
      @srgb ||= SRGB.new(
        *map { |c| (c > 0.0031308 ? 1.055 * (c**(1/2.4)) - 0.055 : 12.92 * c) * 255 },
        linear: self
      )
    end

    def relative_luminance
      @relative_luminance ||= D65_2.RGB2XYZ_matrix(self.class.primaries)
        .row(1).zip(self).map { |(coeff, coord)| coeff * coord }.reduce(&:+)
    end

    def blend(other, weight)
      weight = [0.0, [1.0, weight].min].max
      selfweight = 1.0 - weight
      self.class.new(*zip(other).map { |(c1, c2)| c1 * selfweight + c2 * weight })
    end
  end

  class SRGB
    include Enumerable

    def initialize(r, g, b, linear: nil)
      @r, @g, @b = r, g, b
      @linear = linear
    end

    def each(&b)
      [@r, @g, @b].each(&b)
    end

    def srgb
      self
    end

    def relative_luminance
      linear.relative_luminance
    end

    def blend(other, weight)
      linear.blend(other.linear, weight).srgb
    end

    def cap
      self.class.new(*map { |c| [0, [255, c.round].min].max })
    end

    def hex
      @hex ||= format("#%02x%02x%02x", *cap)
    end

    alias to_s hex

  protected

    def linear
      @linear ||= LinearSRGB.new(
        *map { |c| c/255.0 }
        .map { |c| c <= (12.92 * 0.0031308) ? c / 12.92 : ((c + 0.055)/1.055)**2.4 }
      )
    end
  end
end

class Palette
  include Enumerable

  def initialize
    raise ArgumentError, 'a block is required' unless block_given?
    yield self
    freeze
  end

  def add(name, color, index = @palette&.size || 0, **meta)
    tone = Tone.new(name, color, index, **meta)
    (@palette ||= []) << tone
    define_singleton_method(name) { tone }
  end

  def get(name)
    (@palette ||= []).detect { |tone| tone.name == name }
  end

  def each(&block)
    (@palette ||= []).map { |tone| [tone.name, tone] }.each(&block)
  end

  class Tone
    include Enumerable

    attr_reader :name, :color, :index

    def initialize(name, color, index,
                   background: false, foreground: false,
                   accent: false, alternate: false)
      @name = name
      @color = color
      @index = index
      @background = background
      @foreground = foreground
      @accent = accent
      @alternate = alternate
    end

    def srgb
      @color.srgb.cap
    end

    def each(&block)
      srgb.each(&block)
    end

    def to_s
      srgb.to_s
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
    @dark ||= Palette.new do |dark|
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
    end
  end

  def light
    @light ||= Palette.new do |light|
      light.add(:bg, @fg, background: true)
      light.add(:fg, @bg, foreground: true)
      @colors.keys.each do |name|
        color = dark.get(:"#{name}0").color.reflect_l(@bg, @fg)
        light.add(:"#{name}0", color, accent: true)
        light.add(:"#{name}1", color.blend(@fg, 0.25), accent: true)
        light.add(:"#{name}2", color.blend(@fg, 0.75), background: true)
      end
      grayscale do |weight, meta, index|
        light.add(:"gray#{index}", @fg.blend(@bg, weight), meta)
      end
    end
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
  black = Color::CIELUV.new(13, 3, 5),
  white = Color::CIELUV.new(78, 21, 31),
  red: Color::CIELUV.new(52, 128, 18),
  lime: Color::CIELUV.new(60, 5, 66),
  yellow: Color::CIELUV.new(65, 50, 45),
  purple: Color::CIELUV.new(50, 84, -5),
  orange: Color::CIELUV.new(57, 103, 39),
  cyan: Color::CIELUV.new(60, -30, 1),
)

if $stdout.tty?
  Undefined.dark.zip(Undefined.light).each do |(_, dark, _), (_, light, _)|
    puts([[dark, black, white], [light, white, black]].map do |tone, bgcolor, fgcolor|
      br, bg, bb = bgcolor.srgb.cap.to_a
      fr, fg, fb = fgcolor.srgb.cap.to_a
      rgb = tone.srgb
      cr, cg, cb = rgb.to_a
      f = format("% 4d,% 4d,% 4d", *tone.color.srgb.map(&:round))
      c = format("%0.2f:1", bgcolor.contrast_ratio(rgb))
      "#{f} (#{c}):\x1b[38;2;#{cr};#{cg};#{cb}m\x1b[48;2;#{br};#{bg};#{bb}m#{rgb}\x1b[0m" +
        "\x1b[48;2;#{cr};#{cg};#{cb}m\x1b[38;2;#{fr};#{fg};#{fb}m#{rgb}\x1b[0m"
    end.join)
  end
end
