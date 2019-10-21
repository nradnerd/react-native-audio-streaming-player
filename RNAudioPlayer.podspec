require 'json'
pjson = JSON.parse(File.read('package.json'))

Pod::Spec.new do |s|

  s.name            = "RNAudioPlayer"
  s.version         = pjson["version"]
  s.homepage        = "https://github.com/nradnerd/react-native-audio-streaming-player"
  s.summary         = pjson["description"]
  s.license         = pjson["license"]
  s.author          = { "No Author" => "noauthor@example.org" }
  
  s.ios.deployment_target = '10.0'
  s.tvos.deployment_target = '9.2'

  s.source          = { :git => "https://github.com/nradnerd/react-native-audio-streaming-player", :tag => "v#{s.version}" }
  s.source_files    = "ios/**/*.{h,m}"
  s.preserve_paths  = "**/*.js"

  s.dependency 'React'
end