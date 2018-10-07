require 'matrix'

module Undefined
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

    def relative_luminance
      xyz.y/100.0
    end

    def inspect
      "CIE L*u*v* (#{to_a.join(',')})"
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
      x = 0.0 if x.nan?
      z = 0.0 if z.nan?
      @xyz = CIEXYZ.new(x, y, z)
    end

    def linear_srgb
      @linear_srgb ||= xyz.linear_srgb(@illuminant)
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

    def cieluv(illuminant)
      # Code adapted from http://www.easyrgb.com/en/math.php.
      varu = (4 * x) / (x + (15 * y) + (3 * z))
      varv = (9 * y) / (x + (15 * y) + (3 * z))
      vary = y/100.0
      if vary > 0.008856
        vary = vary**(1/3.0)
      else
        vary = 7.787 * vary + 16.0/116.0
      end
      refu = (4 * illuminant.refx)/(illuminant.refx + (15 * illuminant.refy) + (3 * illuminant.refz))
      refv = (9 * illuminant.refy)/(illuminant.refx + (15 * illuminant.refy) + (3 * illuminant.refz))
      l = 116 * vary - 16
      u = 13 * l * (varu - refu)
      v = 13 * l * (varv - refv)
      u = 0.0 if u.nan?
      v = 0.0 if v.nan?
      CIELUV.new(l, u, v, illuminant: illuminant)
    end

    def linear_srgb(illuminant)
      LinearSRGB.new(*(
        illuminant.XYZ2RGB_matrix(LinearSRGB.primaries) *
        Vector[*map { |c| c/100.0 }]
      ))
    end
  end

  class LinearSRGB
    # This class assumes D65 illuminant as the viewing condition.  An
    # interesting discussion about adapting to other illuminants can be found
    # in https://ninedegreesbelow.com/photography/srgb-luminance.html.
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

    def cieluv
      @cieluv ||= xyz.cieluv(D65_2)
    end

  private

    def xyz
      CIEXYZ.new(*(
        D65_2.RGB2XYZ_matrix(LinearSRGB.primaries) *
        Vector[*self] *
        100.0
      ))
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

    def cieluv
      @cieluv ||= linear.cieluv
    end

  protected

    def linear
      @linear ||= LinearSRGB.new(
        *map { |c| c/255.0 }
        .map { |c| c <= (12.92 * 0.0031308) ? c / 12.92 : ((c + 0.055)/1.055)**2.4 }
      )
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
      detect { |tone| tone.name == name }
    end

    def each(&block)
      (@palette ||= []).each(&block)
    end
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
          color1 = color.blend(@bg, 0.25)
          color2 = color.blend(@bg, 0.75)
          dark.add(:"#{name}0", color, accent: true)
          dark.add(:"#{name}1", color1, accent: true)
          dark.add(:"#{name}2", color2, background: true)
        end
        grayscale do |weight, meta, index|
          color = @bg.blend(@fg, weight)
          dark.add(:"gray#{index}", color, meta)
        end
      end
    end

    def light
      @light ||= Palette.new do |light|
        light.add(:bg, @fg, background: true)
        light.add(:fg, @bg, foreground: true)
        @colors.keys.each do |name|
          color = dark.get(:"#{name}0").color.reflect_l(@bg, @fg)
          color1 = color.blend(@fg, 0.25)
          color2 = color.blend(@fg, 0.75)
          light.add(:"#{name}0", color, accent: true)
          light.add(:"#{name}1", color1, accent: true)
          light.add(:"#{name}2", color2, background: true)
        end
        grayscale do |weight, meta, index|
          color = @fg.blend(@bg, weight)
          light.add(:"gray#{index}", color, meta)
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

  class ContrastRatio
    include Comparable

    def initialize(color1, color2)
      @value = [color1.relative_luminance, color2.relative_luminance]
        .sort.reverse.map { |y| y + 0.05 }.reduce(&:/)
    end

    def <=>(other)
      @value <=> other.to_f
    end

    def to_f
      @value
    end

    def to_s
      format('%0.2f:1', @value)
    end
  end

  class << self
    def dark
      scheme.dark
    end

    def light
      scheme.light
    end

  private

    def scheme
      @scheme ||= Scheme.new(
        CIELUV.new(13, 3, 5),
        CIELUV.new(77, 21, 31),
        red: CIELUV.new(47, 133, 26),
        lime: CIELUV.new(60, 5, 66),
        yellow: CIELUV.new(65, 50, 45),
        purple: CIELUV.new(50, 84, -5),
        orange: CIELUV.new(57, 103, 39),
        cyan: CIELUV.new(60, -30, 1),
      )
    end
  end
end

if __FILE__ == $0
  Undefined.dark.zip(Undefined.light).each do |dark_tone, light_tone|
    black = Undefined.dark.bg.color
    white = Undefined.dark.fg.color
    row = [[dark_tone, black, white], [light_tone, white, black]]
    puts(row.map do |tone, bgcolor, fgcolor|
      br, bg, bb = bgcolor.srgb.cap.to_a
      fr, fg, fb = fgcolor.srgb.cap.to_a
      cr, cg, cb = tone.srgb.to_a
      f = format("% 4d,% 4d,% 4d", *tone.color.srgb.map(&:round))
      c = Undefined::ContrastRatio.new(bgcolor, tone.srgb)
      "#{f} #{c}"\
        "\x1b[38;2;#{cr};#{cg};#{cb}m\x1b[48;2;#{br};#{bg};#{bb}m#{tone}\x1b[0m"\
        "\x1b[48;2;#{cr};#{cg};#{cb}m\x1b[38;2;#{fr};#{fg};#{fb}m#{tone}\x1b[0m"
    end.join(' '))
  end
end
