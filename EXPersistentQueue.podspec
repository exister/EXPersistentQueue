Pod::Spec.new do |s|
  s.name         = 'EXPersistentQueue'
  s.version      = '0.0.1'
  s.license      = 'MIT'
  s.summary      = 'A persistent background job queue for iOS.'
  s.homepage     = 'https://github.com/exister/EXPersistentQueue'
  s.authors      = {'Mikhail Kuznetsov' => 'mkuznetsov.dev@gmail.com'}
  s.source       = { :git => 'https://github.com/exister/EXPersistentQueue.git', :tag => '0.0.1' }
  s.platform     = :ios, '5.0'
  s.source_files = 'EXPersistentQueue/EXPersistentQueue/Classes/*.{h,m}'
  s.requires_arc = true

  s.library      = 'sqlite3.0'

  s.dependency 'FMDB', '~> 2.0'
  s.dependency 'CocoaLumberjack'

  s.prefix_header_contents = '#import "DDLog.h"'
end