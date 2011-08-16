#
#  project_controller.rb
#  macistrano
#
#  Created by Pom on 24.04.08.
#  Copyright (c) 2008 Paperplanes, Mathias Meyer. All rights reserved.
#

require 'osx/cocoa'
require 'rubygems'
require 'notification_hub'
require 'growl_support'

class ProjectController < OSX::NSWindowController
  include OSX, NotificationHub, GrowlSupport
    
  notify :add_host, :when => :host_fully_loaded
  notify :remove_host, :when => :host_removed
  notify :remove_loading, :when => :all_hosts_loaded
  notify :build_completed, :when => :stage_build_completed
  notify :build_running, :when => :stage_build_running
  notify :update_status_window, :when => :deployment_status_updated
  
  attr_reader :status_menu, :webistrano_controller, :quick_deploy_menu_item
  attr_accessor :loaded, :growl_notifier
   
  ib_outlet :run_task_dialog
  ib_outlet :task_field
  ib_outlet :description_field
  ib_outlet :preferences_controller
  ib_outlet :status_hud_window
  ib_outlet :status_hud_window_text
  ib_outlet :show_status_window_checkbox
  ib_outlet :deployment_status_spinner
  ib_outlet :quick_deploy_window
  ib_outlet :quick_deploy_text_field
  ib_outlet :quick_deploy_table
  ib_outlet :project_label
  ib_outlet :stage_label
  
  ib_action :show_about do
    NSApp.orderFrontStandardAboutPanel self
  end
  
  ib_action :show_status do
    @status_hud_window.makeKeyAndOrderFront(self)
  end
  
  def awakeFromNib
    @webistrano_controller = WebistranoController.alloc.init
    @status_menu = NSMenu.alloc.init
    @hotkey_center = DDHotKeyCenter.alloc.init
    show_preferences(self) if @preferences_controller.hosts.empty?
    webistrano_controller.hosts = @preferences_controller.hosts
    create_status_bar
    init_growl
  end
  
  def remove_loading(notification)
    item = status_menu.itemWithTitle("Loading...")
    status_menu.removeItem(item) unless item.nil?
    set_status_icon 'webistrano-small'
    # Disable this for now - it's too costly with lots of projects
    # webistrano_controller.setup_build_check_timer
    
    item = status_menu.itemWithTitle("Quick Deploy")
    item.setTarget self
    item.setEnabled true
  end
  
  def add_host(notification)
    notification.object.projects.each do |project|
      item = status_menu.insertItemWithTitle_action_keyEquivalent_atIndex_(project.name.to_s, "project_clicked:", "", 0)
      item.setTarget self
      item.setRepresentedObject project
      add_stages project
    end
  end
  
  def remove_host(notification)
    host = notification.object
    status_menu.itemArray.each do |item|
      if item.representedObject.is_a?(Project)
        status_menu.removeItem(item) if item.representedObject.host.eql?(host)
      end
    end
  end
  
  def build_running(notification)
    set_status_icon("success-building")
    set_stage_submenu_enabled(notification.object, false, "success-building")
    @deployment_status_spinner.startAnimation(self)
    webistrano_controller.setup_deployment_status_timer(notification.object)
  end
  
  def set_stage_submenu_enabled(deployment, enabled, icon)
    index = status_menu.indexOfItemWithRepresentedObject deployment.stage.project
    unless index == -1
      project_menu = status_menu.itemAtIndex(index).submenu
      stage_menu_index = project_menu.indexOfItemWithRepresentedObject deployment.stage
      stage_menu_item = project_menu.itemAtIndex(stage_menu_index)
      stage_menu_item.setImage get_icon(icon)
      stage_menu = stage_menu_item.submenu
      stage_menu.itemArray.each do |item|
        item.setEnabled enabled
      end
    end
  end
  
  def update_status_window(notification)
    @status_hud_window_text.setString notification.object.log
    range = NSRange.new(@status_hud_window_text.string.length, 0)
    @status_hud_window_text.scrollRangeToVisible range
  end
  
  def build_completed(notification)
    set_stage_submenu_enabled(notification.object, true, notification.object.status)
    set_status_icon(notification.object.status)
    notify_growl(notification)
    @webistrano_controller.remove_deployment_timer(notification)
    @deployment_status_spinner.stopAnimation(self)
  end

  def set_status_icon(icon)
    @statusItem.setImage get_icon(icon)
  end
  
  def get_icon(icon)
    path = NSBundle.mainBundle.pathForResource_ofType("icon-#{icon}", "png")
    NSImage.alloc.initByReferencingFile(path)
  end
  
  def quit(sender)
    NSApp.stop(nil)
  end

  def show_preferences(sender)
    @preferences_controller.showPreferences
  end
  
  def clicked sender
    show_run_window_for_task(sender.representedObject)
  end
  
  def show_run_window_for_task task
    @selected_stage = task.stage
    project = @selected_stage.project
    @project_label.setStringValue(project.name)
    @stage_label.setStringValue(@selected_stage.name)
    @task_field.setStringValue task.name
    
    NSApp.activateIgnoringOtherApps(true)
    @run_task_dialog.makeFirstResponder(@description_field)
    @run_task_dialog.makeKeyAndOrderFront(self)
    @run_task_dialog.center
  end
  
  def stage_clicked(sender)
    url = NSURL.URLWithString sender.representedObject.url
    NSWorkspace.sharedWorkspace.openURL url
  end

  def project_clicked sender
    url = NSURL.URLWithString sender.representedObject.url
    NSWorkspace.sharedWorkspace.openURL url
  end
    
  def run_task(sender = nil)
    taskName = @task_field.stringValue.to_s
    description = @description_field.stringValue.to_s
    @selected_stage.run_stage taskName, description
    case @show_status_window_checkbox.state.to_i
    when 1:
      @status_hud_window.center
      show_status
    when 0:
      @status_hud_window.close
    end
    @run_task_dialog.close
    webistrano_controller.setup_one_time_deployment_status_timer
    @deployment_status_spinner.startAnimation(self)
    @status_hud_window_text.setString("Starting Deployment…")
    reset_fields
  end
  ib_action :run_task
  
  def register_quick_deploy_shortcut key_combo
    @hotkey_center.objc_send(
      :registerHotKeyWithKeyCode, key_combo["keyCode"],
      :modifierFlags, key_combo["modifierFlags"],
      :target, self,
      :action, "quick_deploy_hotkey_pressed:",
      :object, self
    )
  end
  
  def quick_deploy_hotkey_pressed(sender=nil)
    if @quick_deploy_window.isVisible
      @quick_deploy_window.close
    else
      quick_deploy
    end
  end
  
  def quick_deploy(sender=nil)
    @quick_deploy_window.makeKeyAndOrderFront(self)
    @quick_deploy_text_field.becomeFirstResponder
    NSApp.activateIgnoringOtherApps true
    @objects = []
    @all_objects = []
    @columns = ["Project", "Stage", "Action"]
    @quick_deploy_strings = {}
    @preferences_controller.hosts.each do |host|
      host.projects.each do |project|
        project.stages.each do |stage|
          stage.tasks.each do |task|   
            full_string    = "#{project.name} #{stage.name} #{task.name}"         
            object         = {
              @columns[0]  => project.name,
              @columns[1]  => stage.name,
              @columns[2]  => task.name,
              :full_string => full_string,
              :stage       => stage
            }
            @objects << object
            @all_objects << object
            
            @quick_deploy_strings[object] = full_string
          end
        end
      end 
    end
    controlTextDidChange
  end
  ib_action :quick_deploy
  
  def execute_quick_deploy(sender=nil)
    if @quick_deploy_table.selectedRow
      object = @objects[@quick_deploy_table.selectedRow]
      
      task = Task.new 
      task.stage = object[:stage]
      task.name = object["Action"]
      task.description = task.name
            
      @quick_deploy_window.close      
      show_run_window_for_task task
    end
    
  end
  ib_action :execute_quick_deploy
  
  def numberOfRowsInTableView(aTableView)
    return @objects.length rescue 0
  end
  
  def controlTextDidChange note=nil
    value = @quick_deploy_text_field.stringValue.to_s
    @all_objects.sort! do |a, b|
      a[:scores] ||= {}
      a[:scores][value] ||= a[:full_string].score(value)
      b[:scores] ||= {}
      b[:scores][value] ||= b[:full_string].score(value)
      
      b[:scores][value] <=> a[:scores][value]
    end
    @objects = @all_objects.clone
    @objects.delete_if do |object|
      object[:scores][value] == 0.0
    end
    index = NSIndexSet.indexSetWithIndex 0
    @quick_deploy_table.selectRowIndexes_byExtendingSelection index, false
    @quick_deploy_table.reloadData
  end
  

  def tableView_objectValueForTableColumn_row(afileTable, aTableColumn, rowIndex)
    @columns.each do |column|
      if aTableColumn.headerCell.stringValue == column
  	    object = @objects[rowIndex]
    	  return object[column]
      end
    end
  end
  ib_action :closeTaskWindow do
    @run_task_dialog.close
    reset_fields
  end
  
  def add_stages(project)
    idx = status_menu.indexOfItemWithRepresentedObject(project)
    if idx >= 0
      item = status_menu.itemAtIndex(idx)
      sub_menu = NSMenu.alloc.init
      lastIndex = 0
      project.stages.each do |stage|
        sub_item = sub_menu.insertItemWithTitle_action_keyEquivalent_atIndex_(stage.name, "stage_clicked:", "", lastIndex)
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
    tasks_menu.setAutoenablesItems false
    stage_menu_item.setSubmenu tasks_menu
    stage_menu_item.setEnabled true
  end
  
  private
  
  def reset_fields
    @task_field.setStringValue ""
    @description_field.setStringValue ""
  end
   
  def create_status_bar
    @statusItem = NSStatusBar.systemStatusBar.statusItemWithLength(NSVariableStatusItemLength)
    set_status_icon 'webistrano-small-disabled'
    @statusItem.setHighlightMode true
    @statusItem.setMenu @status_menu
    @statusItem.setTarget self
    update_menu
  end
   
  def update_menu(hosts_list = nil)
    # Loading...
    item = NSMenuItem.alloc.initWithTitle_action_keyEquivalent("Loading...", nil, "")
    item.setEnabled false
    status_menu.insertItem_atIndex(item, status_menu.numberOfItems)

    # -----
    status_menu.insertItem_atIndex(NSMenuItem.separatorItem, status_menu.numberOfItems)
    
    # Quick Deploy
    
    @quick_deploy_menu_item = NSMenuItem.alloc.initWithTitle_action_keyEquivalent("Quick Deploy", "quick_deploy:", "")
    @quick_deploy_menu_item.setEnabled false
    status_menu.insertItem_atIndex(@quick_deploy_menu_item, status_menu.numberOfItems)
    
    # Show Status Window
    item = status_menu.insertItemWithTitle_action_keyEquivalent_atIndex_("Show Status Window", "show_status:", "", status_menu.numberOfItems)
    item.setTarget self

    # Preferences
    item = status_menu.insertItemWithTitle_action_keyEquivalent_atIndex_("Preferences", "show_preferences:", "", status_menu.numberOfItems)
    item.setTarget self
    
    # About
    item = status_menu.insertItemWithTitle_action_keyEquivalent_atIndex_("About", "show_about:", "", status_menu.numberOfItems)
    item.setTarget self
    status_menu.insertItem_atIndex(NSMenuItem.separatorItem, status_menu.numberOfItems)

    # Quit
    item = status_menu.insertItemWithTitle_action_keyEquivalent_atIndex_("Quit", "quit:", "", status_menu.numberOfItems)
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
