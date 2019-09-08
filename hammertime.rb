require_relative './undefined'

module Undefined
  Hammertime = Scheme.new(
    CIELUV.new(13, 1.8, -0.6),
    CIELUV.new(87, 12.7, -16.4),
    red: CIELUV.new(58, 97, -20),
    lime: CIELUV.new(58, -7, 45),
    yellow: CIELUV.new(58, 47, 20),
    purple: CIELUV.new(58, 9, -84),
    orange: CIELUV.new(58, 97, 32),
    cyan: CIELUV.new(58, -33, 4),
  )

  Hammertime.print if __FILE__ == $0
end
