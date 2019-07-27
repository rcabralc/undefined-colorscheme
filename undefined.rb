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
      selfweight = 1.0 - weight
      self.class.new(*zip(other).map { |(c1, c2)| c1 * selfweight + c2 * weight })
    end

    def reflect_l(dark, light)
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
      @swatches = []
      yield self
      freeze
    end

    def add(color, name, *aliases, **meta)
      index = @swatches.size
      swatch = Swatch.new(self, index, color, name, *aliases, **meta)
      @swatches << swatch
      define_singleton_method(name) { swatch }
      aliases.each { |a| define_singleton_method(a) { swatch } }
    end

    def get(name)
      detect { |swatch| swatch.known_by?(name) }
    end

    def each(&block)
      @swatches.each(&block)
    end
  end

  class Swatch
    include Enumerable

    attr_reader :color, :name, :aliases, :index

    def initialize(palette, index, color, name, *aliases,
                   background: false, foreground: false,
                   accent: false, alternate: false)
      @palette = palette
      @name = name
      @aliases = aliases
      @color = color
      @index = index
      @background = background
      @foreground = foreground
      @accent = accent
      @alternate = alternate
    end

    def known_by?(name)
      @name == name || @aliases.include?(name)
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

    def description
      f = format("% 4d,% 4d,% 4d", *srgb_ints)
      c = ContrastRatio.new((background? ? @palette.fg : @palette.bg).srgb, srgb)
      "#{f} #{c} #{usage} #{print(size: 2)}"
    end

    def print(bg: background? ? srgb : @palette.bg.srgb,
              fg: background? ? @palette.fg.srgb : srgb,
              size: 0)
      "\x1b[#{bg_es(bg)}\x1b[#{fg_es(fg)}#{self}\x1b[0m"\
        "\x1b[#{bg_es}#{' ' * size}\x1b[0m"
    end

  private

    def usage
      [alternate? ? 'A' : ' ',
       background? ? 'B' : ' ',
       foreground? ? 'F' : ' '].join
    end

    def srgb_ints
      color.srgb.map(&:round)
    end

    def bg_es(color = self)
      "48;2;#{color.to_a.join(';')}m"
    end

    def fg_es(color = self)
      "38;2;#{color.to_a.join(';')}m"
    end
  end

  class Scheme
    def initialize(bg, fg, **colors)
      raise ArgumentError, "define exactly six colors" if colors.size != 6
      @bg = bg
      @fg = fg
      @colors = colors
    end

    def dark
      @dark ||= Palette.new do |dark|
        dark.add(@bg, :bg, :term0, background: true)
        dark.add(@fg, :fg, :term15, foreground: true)
        dark.add(@bg.blend(@fg, -0.06), :altbg, :term16, background: true, alternate: true)
        @colors.each.with_index do |(name, color), index|
          color1 = color.blend(@bg, 0.25)
          bg1 = color.blend(@bg, 0.50)
          bg2 = color.blend(@bg, 0.63)
          bg3 = color.blend(@bg, 0.75)
          dark.add(color, :"#{name}0", :"term#{index + 9}", accent: true)
          dark.add(color1, :"#{name}1", :"term#{index + 1}", accent: true)
          dark.add(bg1, :"#{name}2", :"term#{index + 9}_1", background: true)
          dark.add(bg2, :"#{name}2", :"term#{index + 9}_2", background: true)
          dark.add(bg3, :"#{name}3", :"term#{index + 9}_3", background: true, alternate: true)
        end
        grayscale do |weight, meta, index|
          color = @bg.blend(@fg, weight)
          alias_ = meta.delete(:alias)
          dark.add(color, :"gray#{index}", alias_, **meta)
        end
      end
    end

    def light
      @light ||= Palette.new do |palette|
        black = CIELUV.new(0, 0, 0)
        white = CIELUV.new(100, 0, 0)
        dark.each do |swatch|
          palette.add(swatch.color.reflect_l(black, white),
                      swatch.name,
                      *swatch.aliases,
                      background: swatch.background?,
                      foreground: swatch.foreground?,
                      accent: swatch.accent?,
                      alternate: swatch.alternate?)
        end
      end
    end

    def print
      if ARGV[0] == 'compare'
        [[0, 0], [0, 1], [1, 1], [2, 2], [2, 3], [3, 3]].each do |t1, t2|
          header = [dark, light].flat_map do |palette|
            ["  #{t1}x#{t2}  ", *@colors.keys.map do |n|
              palette.get(:"#{n}#{t1}").print
            end]
          end
          puts(header.join)
          @colors.keys.each do |b|
            row = [dark, light].flat_map do |palette|
              base = palette.get(:"#{b}#{t2}")
              contrasts = @colors.keys.map do |n|
                ContrastRatio.new(base.srgb, palette.get(:"#{n}#{t1}").srgb)
              end
              [base.print, *contrasts.map { |c| " #{c}" }]
            end
            puts(row.join)
          end
        end
      else
        dark.zip(light).each do |dark_swatch, light_swatch|
          puts("#{dark_swatch.description} #{light_swatch.description} #{dark_swatch.aliases.join(' ')}")
        end
      end
    end

  private

    def grayscale(&block)
      [
        [0.05, { alias: :term17, alternate: true, background: true }],
        [0.1, { alias: :term18 }],
        [0.25, { alias: :term8 }],
        [0.38, { alias: :term19 }],
        [0.5, { alias: :term7, accent: true }],
        [0.85, { alias: :term20, alternate: true, foreground: true }],
      ].each_with_index do |(weight, meta), index|
        yield weight, meta, index
      end
    end
  end

  class ContrastRatio
    include Comparable

    def initialize(color1, color2)
      @value = [color1.relative_luminance, color2.relative_luminance]
        .sort.reverse.map { |y| y + 0.05 }.reduce(&:'/')
    end

    def <=>(other)
      @value <=> other.to_f
    end

    def to_f
      @value
    end

    def to_s
      format('%5.2f:1', @value)
    end
  end

  Undefined = Scheme.new(
    CIELUV.new(11, 6, 8),
    CIELUV.new(89, 24, 37),
    red: CIELUV.new(50, 154, 23),
    lime: CIELUV.new(60, -6, 67),
    yellow: CIELUV.new(65, 50, 45),
    purple: CIELUV.new(50, 97, -9),
    orange: CIELUV.new(50, 103, 43),
    cyan: CIELUV.new(60, -48, 0),
  )

  def self.dark
    Undefined.dark
  end

  def self.light
    Undefined.light
  end

  Undefined.print if __FILE__ == $0
end
