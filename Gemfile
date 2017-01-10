##
# Amazon Payments - Login and Pay for Spree Commerce
#
# @category    Amazon
# @package     Amazon_Payments
# @copyright   Copyright (c) 2014 Amazon.com
# @license     http://opensource.org/licenses/Apache-2.0  Apache License, Version 2.0
#
##
source 'https://rubygems.org'

branch = ENV.fetch('SOLIDUS_BRANCH', 'master')
gem "solidus", github: "solidusio/solidus", branch: branch

group :development, :test do
  gem 'pry-rails'
end

group :test do
  gem 'codeclimate-test-reporter', require: nil
  gem 'webmock'
end

gemspec
