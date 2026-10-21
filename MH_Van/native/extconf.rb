# frozen_string_literal: true

require 'mkmf'

$CFLAGS = "#{CONFIG['CFLAGS']} -O3"
create_makefile('mh_van_native')
