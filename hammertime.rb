require_relative './undefined'

module Undefined
  Hammertime = Scheme.new(
    CIELUV.new(13, 1.8, -0.6),
    CIELUV.new(87, 12.7, -16.4),
    red: CIELUV.new(59, 97, -20),
    lime: CIELUV.new(59, -7, 45),
    yellow: CIELUV.new(59, 47, 20),
    purple: CIELUV.new(59, 9, -84),
    orange: CIELUV.new(59, 97, 32),
    cyan: CIELUV.new(59, -33, 4),
  )

  Hammertime.print if __FILE__ == $0
end
