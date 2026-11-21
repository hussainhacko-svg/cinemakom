Pod::Spec.new do |s|
  s.name             = 'wakelock_plus'
  s.version          = '0.0.1'
  s.summary          = 'Local tvOS shim for wakelock_plus 1.8.2 (whose upstream podspec depends on the iOS-only Flutter pod).'
  s.description      = 'Provides the wakelock_plus module for tvOS GeneratedPluginRegistrant without modifying pub cache or iOS builds.'
  s.homepage         = 'https://github.com/sharon-xa/cinemakom'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Cinemakom' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{h,m}'
  s.public_header_files = 'Classes/**/*.h'
  s.platform         = :tvos, '15.0'
  s.xcconfig         = {
    'FRAMEWORK_SEARCH_PATHS' => '"${PODS_ROOT}/../Flutter"',
  }
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
