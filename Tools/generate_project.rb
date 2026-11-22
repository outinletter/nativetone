#!/usr/bin/env ruby
# Generates NativeTone.xcodeproj (app + keyboard extension). Run from the project root:
#   ruby Tools/generate_project.rb
require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
Dir.chdir(ROOT)

APP_NAME   = 'NativeTone'
KB_NAME    = 'NativeToneKeyboard'
BUNDLE_ID  = 'com.addvalue.nativetone'
KB_BUNDLE  = "#{BUNDLE_ID}.keyboard"
DEPLOY     = '17.0'

FileUtils.rm_rf("#{APP_NAME}.xcodeproj")
proj = Xcodeproj::Project.new("#{APP_NAME}.xcodeproj")
proj.root_object.attributes['LastUpgradeCheck'] = '2600'

app = proj.new_target(:application, APP_NAME, :ios, DEPLOY)
kb  = proj.new_target(:app_extension, KB_NAME, :ios, DEPLOY)

def swift_files(dir)
  Dir.glob("#{dir}/**/*.swift").sort
end

shared_group = proj.main_group.new_group('Shared', 'Shared')
app_group    = proj.main_group.new_group('App', 'App')
kb_group     = proj.main_group.new_group('Keyboard', 'Keyboard')

shared_refs = swift_files('Shared').map { |f| shared_group.new_file(File.basename(f)) }
app_refs    = swift_files('App').map    { |f| app_group.new_file(File.basename(f)) }
kb_refs     = swift_files('Keyboard').map { |f| kb_group.new_file(File.basename(f)) }

app.add_file_references(shared_refs + app_refs)
kb.add_file_references(shared_refs + kb_refs)

assets = app_group.new_file('Assets.xcassets')
app.resources_build_phase.add_file_reference(assets)
app_group.new_file('Info.plist')
app_group.new_file('NativeTone.entitlements')
kb_group.new_file('Info.plist')
kb_group.new_file('NativeToneKeyboard.entitlements')

common = {
  'SWIFT_VERSION' => '5.0',
  'IPHONEOS_DEPLOYMENT_TARGET' => DEPLOY,
  'TARGETED_DEVICE_FAMILY' => '1',
  'MARKETING_VERSION' => '1.0',
  'CURRENT_PROJECT_VERSION' => '1',
  'GENERATE_INFOPLIST_FILE' => 'NO',
  'DEVELOPMENT_TEAM' => 'A7QB8PT33N',
  'CODE_SIGN_STYLE' => 'Automatic',
  'SWIFT_EMIT_LOC_STRINGS' => 'YES',
}

app.build_configurations.each do |c|
  c.build_settings.merge!(common)
  c.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => BUNDLE_ID,
    'INFOPLIST_FILE' => 'App/Info.plist',
    'CODE_SIGN_ENTITLEMENTS' => 'App/NativeTone.entitlements',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks'],
  )
end

kb.build_configurations.each do |c|
  c.build_settings.merge!(common)
  c.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => KB_BUNDLE,
    'INFOPLIST_FILE' => 'Keyboard/Info.plist',
    'CODE_SIGN_ENTITLEMENTS' => 'Keyboard/NativeToneKeyboard.entitlements',
    'SKIP_INSTALL' => 'YES',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
  )
end

# Embed the keyboard extension into the app.
app.add_dependency(kb)
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
build_file = embed.add_file_reference(kb.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

proj.save
Xcodeproj::XCScheme.share_scheme(proj.path, APP_NAME) if Xcodeproj::XCScheme.respond_to?(:share_scheme) && proj.recreate_user_schemes
puts "Generated #{APP_NAME}.xcodeproj"
