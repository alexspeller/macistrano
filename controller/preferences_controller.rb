require 'osx/cocoa'

class PreferencesController < OSX::NSWindowController
  attr_accessor :hosts
  include OSX
  include NotificationHub

  notify :host_version_accepted, :when => :host_version_acceptable
  notify :host_version_not_accepted, :when => :host_version_inacceptable
  notify :host_credentials_invalid, :when => :host_credentials_invalid
  notify :host_check_failed, :when => :host_check_failed
  
  ib_outlet :preferences_window
  ib_outlet :table_view
  ib_outlet :new_host_sheet
  ib_outlet :spinner
  ib_outlet :host_field
  ib_outlet :username_field
  ib_outlet :password_field
  ib_outlet :quick_deploy_hotkey_recorder
  ib_outlet :project_controller
  
  def init
    init_hosts
    self
  end


  def awakeFromNib
    init_key_combo
  end
  
  def register_defaults
    appDefaults = NSMutableDictionary.dictionary
    appDefaults.setObject_forKey([], "hosts")
    appDefaults.setObject_forKey([], "keyCombo")
    NSUserDefaults.standardUserDefaults.registerDefaults appDefaults
  end
  
  def init_hosts
    register_defaults
    configured_hosts = NSUserDefaults.standardUserDefaults.arrayForKey("hosts")
    @hosts ||= []
    configured_hosts.each do |data|
      host = Host.alloc.init
      host.url = data[0]
      host.username = data[1]
      Keychain.find_password host
      @hosts << host
    end
    fetchPasswords
  end
  
  def init_key_combo
    if read_key_combo
      set_menu_item_key_combo
      @project_controller.register_quick_deploy_shortcut(@key_combo)
    end
  end
  
  def read_key_combo
    array = NSUserDefaults.standardUserDefaults.arrayForKey("keyCombo")
    return nil unless array.length == 3
    @key_combo = {
      "characters"    => array[0],
      "keyCode"       => array[1],
      "modifierFlags" => array[2]
    }
  end
  
  def fetchPasswords
    @hosts.each do |host|
      Keychain.find_password host
    end
  end
  
  def showPreferences
    NSApp.activateIgnoringOtherApps true
    self.showWindow(self)
    @preferences_window.makeKeyAndOrderFront(self)
  end
  
  def numberOfRowsInTableView(table_view)
    @hosts.size
  end
  
  def tableView_objectValueForTableColumn_row(table_view, column, row)
    @hosts[row].url
  end
  
  ib_action :add do
    NSApp.beginSheet_modalForWindow_modalDelegate_didEndSelector_contextInfo(@new_host_sheet, @preferences_window, nil, nil, nil)
    NSApp.endSheet @new_host_sheet
  end
  
  ib_action :addFromSheet do
    @spinner.startAnimation(self)
    @spinner.setHidden(false)
    host = Host.new
    host.url = @host_field.stringValue
    host.username = @username_field.stringValue
    host.password = @password_field.stringValue.to_s
    host.schedule_version_check
  end

  def host_version_accepted(notification)
    # ignore messages to instances not connected to the nib. weird side effect of having an instance
    # of the controller in the project_controller
    return if @host_field.nil?
    host = notification.object
    add_host host
    @new_host_sheet.orderOut self
    @table_view.reloadData
    host.find_projects
  end
  
  def host_check_failed(notification)
    return if @host_field.nil?
    host = notification.object
    show_alert("There was an error trying to fetch the data for the host, are you sure the URL is correct?", "Please have a good look at the data and try again.")
    reset_spinner
  end
  
  def host_version_not_accepted(notification)
    return if @host_field.nil?
    host = notification.object
    show_alert("The Webistrano version you're running is not suitable for use with Macistrano", "You need at least version #{Host::ACCEPT_VERSION.join(".")}.")
    reset_spinner
  end

  def host_credentials_invalid(notification)
    return if @host_field.nil?
    show_alert("The specified credentials are invalid.", "Please check username and password and try again.")
    reset_spinner
  end
  
  def show_alert(message, extended)
    alert = NSAlert.alloc.init
    alert.addButtonWithTitle "OK"
    alert.setMessageText message
    alert.setInformativeText extended
    alert.setAlertStyle NSWarningAlertStyle
    alert.runModal
    alert.release
  end
  
  def reset_spinner
    @spinner.stopAnimation(self)
    @spinner.setHidden(true)
  end
  
  ib_action :cancelSheet do
    closeSheet
    reset_fields
    reset_spinner
  end

  ib_action :removeHost do
    unless @table_view.selectedRow < 0
      host = @hosts[@table_view.selectedRow]
      Keychain.remove_password host
      @hosts.delete_at(@table_view.selectedRow)
      save_hosts_to_preferences
      notify_host_removed host
      @table_view.reloadData
    end
  end
  
  def closeSheet
    @new_host_sheet.orderOut self
  end
  
  def add_host host
    @hosts << host
    Keychain.add_password host
    save_hosts_to_preferences
    reset_fields
    reset_spinner
  end
  
  def save_hosts_to_preferences
    NSUserDefaults.standardUserDefaults.setObject_forKey(hosts_as_list, "hosts")
    NSUserDefaults.standardUserDefaults.synchronize
  end
  
  def key_combo_as_list
    [@key_combo["characters"], @key_combo["keyCode"], @key_combo["modifierFlags"]]
  end
  
  def save_key_combo_to_preferences
    NSUserDefaults.standardUserDefaults.setObject_forKey(key_combo_as_list, "keyCombo")
    NSUserDefaults.standardUserDefaults.synchronize    
  end
  
  def change_quick_deploy_shortcut
    @key_combo = @quick_deploy_hotkey_recorder.objectValue
    
    set_menu_item_key_combo
    
    @project_controller.register_quick_deploy_shortcut(@key_combo)
    save_key_combo_to_preferences
  end
  
  def set_menu_item_key_combo
    return unless @project_controller.quick_deploy_menu_item
    menu_item = @project_controller.quick_deploy_menu_item
    menu_item.setKeyEquivalentModifierMask @key_combo["modifierFlags"]
    menu_item.setKeyEquivalent @key_combo["characters"]
  end
  
  def hosts_as_list
    @hosts.collect do |host|
      [host.url, host.username]
    end
  end
  
  def reset_fields
    @host_field.setStringValue ""
    @new_host_sheet.makeFirstResponder @host_field
    @password_field.setStringValue ""
    @username_field.setStringValue ""
  end
end
