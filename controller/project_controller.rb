#
#  project_controller.rb
#  macistrano
#
#  Created by Pom on 24.04.08.
#  Copyright (c) 2008 Paperplanes, Mathias Meyer. All rights reserved.
#

require 'osx/cocoa'
require 'rubygems'

class ProjectController < OSX::NSWindowController
  include OSX
  include NotificationHub
  
  notify :add_host, :when => :host_fully_loaded
  notify :remove_host, :when => :host_removed
  notify :remove_loading, :when => :all_hosts_loaded
  notify :build_completed, :when => :stage_build_completed
  notify :build_running, :when => :stage_build_running

  attr_reader :status_menu
  attr_accessor :loaded
   
  ib_outlet :runTaskDialog
  ib_outlet :taskField
  ib_outlet :descriptionField
   
  def awakeFromNib
    @webistrano_controller = WebistranoController.alloc.init
    @status_menu = OSX::NSMenu.alloc.init
    @preferences_controller = PreferencesController.alloc.init
    @webistrano_controller.hosts = @preferences_controller.hosts
    create_status_bar
  end
  
  def remove_loading(notification)
    item = @statusItem.menu.itemWithTitle("Loading...")
    @statusItem.menu.removeItem(item) unless item.nil?
    @webistrano_controller.setup_build_check_timer
  end
  
  def add_host(notification)
    notification.object.projects.each do |project|
      item = @statusItem.menu.insertItemWithTitle_action_keyEquivalent_atIndex_("#{project.name.to_s} (#{project.host.url})", nil, "", @statusItem.menu.numberOfItems)
      item.setTarget self
      item.setRepresentedObject project
      add_stages project
    end
  end
  
  def remove_host(notification)
    host = notification.object
    @statusItem.menu.itemArray.each do |item|
      if item.representedObject.is_a?(Project)
        @statusItem.menu.removeItem(item) if item.representedObject.host.eql?(host)
      end
    end
  end
  
  def build_running(notification)
    puts "Build is running for stage #{notification.object.stage.name}"
  end
  
  def build_completed(notification)
    puts "Build completed for stage #{notification.object.stage.name}"
  end
  
  def quit(sender)
    NSApp.stop(nil)
  end

  def show_preferences(sender)
    @preferences_controller.showPreferences
  end
  
  def clicked(sender)
    @runStage = sender.representedObject.stage
    @taskField.setStringValue sender.representedObject.name
    NSApp.activateIgnoringOtherApps true
    @runTaskDialog.makeFirstResponder @descriptionField
    @runTaskDialog.setTitle("Run Task")
    @runTaskDialog.makeKeyAndOrderFront(self)
    @runTaskDialog.center
  end
  
  def add_projects(notification)
    options = notification.object
    options[:projects].each do |project|
      item = @statusItem.menu.insertItemWithTitle_action_keyEquivalent_atIndex_("#{project.name.to_s} (#{project.host.url})", nil, "", @statusItem.menu.numberOfItems)
      item.setTarget self
      item.setRepresentedObject project
    end
  end
  
  ib_action :runTask do
    taskName = @taskField.stringValue.to_s
    description = @descriptionField.stringValue.to_s
    @runStage.run_stage taskName, description
    @runTaskDialog.close
    reset_fields
  end
   
  ib_action :closeTaskWindow do
    @runTaskDialog.close
    reset_fields
  end
  
  def add_stages(project)
    idx = @statusItem.menu.indexOfItemWithRepresentedObject(project)
    if idx >= 0
      item = @statusItem.menu.itemAtIndex(idx)
      sub_menu = NSMenu.alloc.init
      lastIndex = 0
      project.stages.each do |stage|
        sub_item = sub_menu.insertItemWithTitle_action_keyEquivalent_atIndex_(stage.name, nil, "", lastIndex)
        sub_item.setTarget self
        sub_item.setRepresentedObject stage
        lastIndex += 1
        add_tasks(stage, sub_item)
      end
      item.setSubmenu sub_menu
      item.setEnabled true
    end
  end
  
  def add_tasks(stage, parent_item)
    stage_menu_item = parent_item
    
    tasks_menu = NSMenu.alloc.init
    lastIndex = 0
    stage.tasks.each do |task|
      sub_item = tasks_menu.insertItemWithTitle_action_keyEquivalent_atIndex_(task.name, "clicked:", "", lastIndex)
      sub_item.setTarget self
      sub_item.setRepresentedObject task
      lastIndex += 1
    end
    stage_menu_item.setSubmenu tasks_menu
    stage_menu_item.setEnabled true
  end
  
  private
  
  def reset_fields
    @taskField.setStringValue ""
    @descriptionField.setStringValue ""
  end
   
  def create_status_bar
    @statusItem = OSX::NSStatusBar.systemStatusBar.statusItemWithLength(OSX::NSVariableStatusItemLength)
    path = NSBundle.mainBundle.pathForResource_ofType("icon-failure", "png")
    @statusItem.setImage NSImage.alloc.initByReferencingFile(path)
    @statusItem.setHighlightMode true
    @statusItem.setMenu @status_menu
    @statusItem.setTarget self
    update_menu
  end
   
  def update_menu hosts_list = nil
    item = NSMenuItem.alloc.initWithTitle_action_keyEquivalent("Loading...", nil, "")
    item.setEnabled false
    @statusItem.menu.insertItem_atIndex(item, 0)
    
    item = @statusItem.menu.insertItemWithTitle_action_keyEquivalent_atIndex_("Quit", "quit:", "", 1)
    item.setTarget self

    item = @statusItem.menu.insertItemWithTitle_action_keyEquivalent_atIndex_("Preferences", "show_preferences:", "", 2)
    item.setTarget self
    fetch_projects
  end
  
  def fetch_projects
    hosts = @preferences_controller.hosts
    hosts.each do |host|
      host.find_projects
    end
  end
end
