require_relative './undefined'

module Undefined
  Hammertime = Scheme.new(
    CIELUV.new(13.2, 1.8, -0.6),
    CIELUV.new(86.8, 12.7, -16.4),
    red: CIELUV.new(53, 122, -9),
    lime: CIELUV.new(57, -7, 45),
    yellow: CIELUV.new(56, 47, 20),
    purple: CIELUV.new(56, 9, -84),
    orange: CIELUV.new(59, 97, 32),
    cyan: CIELUV.new(56, -33, 3),
  )

  Hammertime.print if __FILE__ == $0
end
