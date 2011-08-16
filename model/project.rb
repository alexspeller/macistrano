#
#  project.rb
#  macistrano
#
#  Created by Pom on 25.04.08.
#  Copyright (c) 2008 __MyCompanyName__. All rights reserved.
#

require 'osx/cocoa'
require 'hpricot'
require 'notification_hub'
require 'host'

class Project < OSX::NSObject
  include NotificationHub
  
  attr_accessor :name, :webistrano_id, :stages, :host
  
  def fully_loaded?
    @stages && @stages.select{|stage| !stage.fully_loaded?}.empty?
  end

  def stages_url
    "#{host.url}/projects/#{self.webistrano_id}/stages.xml"
  end

  def url
    "#{host.url}/projects/#{webistrano_id}"
  end
  
  def fetch_stages doc
    to_stages doc
  end

  
  
  def to_stages doc
    @stages = []

    (doc/'stage').each do |data|
      stage = Stage.alloc.init
      stage.webistrano_id = (data/:id).text
      stage.name = (data/:name).text
      stage.project = self
      @stages << stage
      stage.fetch_tasks data
    end
    @stages
  end
end
