#
#  host.rb
#  macistrano
#
#  Created by Pom on 28.04.08.
#  Copyright (c) 2008 Paperplanes. All rights reserved.
#

require 'open-uri'
require 'rubygems'
require 'hpricot'
require 'notification_hub'
require 'load_operation_queue'

class Host < OSX::NSObject
  include NotificationHub
  
  ACCEPT_VERSION = [1, 3, 1]
  
  attr_accessor :projects, :url, :username, :password
  
  def init
    @projects = []
    self
  end

  def url=(url)
    url = "http://#{url}" unless url.index("http://") == 0 or url.index("https://") == 0
    @url = url
  end
  
  def read_xml(path)
    io = open("#{url}#{path}", :http_basic_authentication => [username, password])
    io.read
  end
  
  def version_url
    "#{url}/sessions/version.xml"
  end
  
  def schedule_version_check
    LoadOperationQueue.queue_request(version_url, self, :username => username, :password => password, :on_success => :version_check_finished, :on_error => :version_check_failed)
  end
  
  def fully_loaded?
    @projects && @projects.select{|project| !project.fully_loaded?}.empty?
  end
  
  
  def load_url_failed(url, error)
    notify_host_load_failed self
  end
  
  def version_check_finished(data)
    if version_acceptable?(data)
      notify_host_version_acceptable self
    else
      notify_host_version_inacceptable self
    end
  end
  
  def version_check_failed(url, error)
    code = error.code unless error.is_a?(Fixnum)
    case code
    when -1003:
      notify_host_unreachable self
    when -1012:
      notify_host_credentials_invalid self
    else
      notify_host_check_failed self
    end
  end
  
  def version_acceptable?(response)
    doc = Hpricot.XML response
    element = doc/'application'
    version = (element/:version).text if (element/:version).any?
    name = (element/:name).text if (element/:name).any?
    version_eql_or_higher(to_version_array(version)) and name == 'Webistrano'
  end
  
  def version_eql_or_higher version
    return false if version.nil? || version.size == 0
    version[1] = 0 if version.size == 1
    version[2] = 0 if version.size == 2
    if version[0] > ACCEPT_VERSION[0]
      true
    elsif version[0] >= ACCEPT_VERSION[0] and version[1] > ACCEPT_VERSION[1]
      true
    elsif version[0] >= ACCEPT_VERSION[0] and version[1] == ACCEPT_VERSION[1] and version[2] >= ACCEPT_VERSION[2]
      true
    else
      false
    end
    
  end
  
  def to_version_array(version)
    unless version == nil || version == ""
      version_parts = version.split(/\./)
      version_parts.each_with_index {|num, index| version_parts[index] = num.to_i}
      version_parts
    end
  end
  
  def collection_url
    "#{url}/projects.xml"
  end
  
  def find_projects
    LoadOperationQueue.queue_request collection_url, self, :username => username, :password => password, :on_error => :find_projects_failed, :on_success => :find_projects_success
  end
  
  def find_projects_failed data, error
    $stderr.puts "Could not find projects:", error
  end
  
  def find_projects_success(data)
    to_projects(data)
    notify_host_fully_loaded(self) 
  end
  
  def to_projects response
    @projects = []
    doc = Hpricot.XML response
    (doc/'project').each do |data|
      project = Project.new
      project.webistrano_id = (data/">id").text
      project.name = (data/">name").first.inner_text
      project.host = self
      @projects << project
      project.fetch_stages(data)
    end
    @projects
  end

  def eql?(host)
    return host.url == self.url && host.username == self.username
  end
end
