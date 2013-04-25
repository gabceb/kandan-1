class User < ActiveRecord::Base
  extend Enumerize

  # Being pesimistic here and making the default waiting for approval for security reasons
  enumerize :registration_status, in: [:active, :suspended, :waiting_approval], :default => :waiting_approval

  devise :omniauthable, :omniauth_providers => [:github]

  has_many :activities
  before_save :ensure_authentication_token
  before_save :ensure_gravatar_hash
  before_create :mark_registration_status_depending_on_app_settings

  after_create :ensure_at_least_one_admin
  after_destroy :ensure_at_least_one_admin
  
  validates :username, :presence => true, :uniqueness => true
  
  # Kandan.devise_modules is defined in config/initializers/kandan.rb
  devise devise *Kandan.devise_modules

  # Setup accessible (or protected) attributes for your model
  attr_accessible :id, :username, :email, :password, :password_confirmation, :remember_me, :first_name, :last_name, :locale, :gravatar_hash, :registration_status, :provider, :uid

  def full_name
    "#{self.first_name.to_s} #{self.last_name.to_s}".titlecase
  end

  def full_name_or_username
    self.full_name.blank? ? self.username : self.full_name
  end

  # Callback to mark the user registration status depending on the settings of the app
  def mark_registration_status_depending_on_app_settings
    # If the site is public we will make the user active. Otherwise we will make the user as waiting_approval
    self.registration_status = Setting.my_settings.public_site? ? :active : :waiting_approval
  end

  def ensure_gravatar_hash
    self.gravatar_hash = Digest::MD5.hexdigest self.email
  end

  # We never want an app without an admin so let's ensure there is at least one user
  def ensure_at_least_one_admin
    if User.count == 1
      u = User.first
      u.is_admin = true
      u.save!
    end
  end

  def active_for_authentication?
    super && active?
  end

  def self.deleted_user
    dummy_user = new(:username => "Deleted User", :gravatar_hash => "", :email => "")
    dummy_user.active = false

    return dummy_user
  end

  def activate
    self.registration_status = "active"
  end

  def activate!
    self.activate && self.save!
  end

  def suspend
    self.registration_status = "suspended"
  end

  def suspend!
    self.suspend && self.save!
  end

  def self.find_or_create_for_github_oauth(auth, signed_in_resource=nil)
    user = User.where(:provider => auth.provider, :uid => auth.uid).first

    name = auth.info.name

    # Split the name in 2 based on the last space
    first = name[name.rindex(" ")..-1]
    last = name[0...name.rindex(" ")]

    if user.nil?
      user = User.create(username: ensure_unique_username(auth.info.nickname), first_name: first, last_name: last, provider:auth.provider, uid:auth.uid, email:auth.info.email, password:Devise.friendly_token[0,20])
    end

    return user
  end

  def self.split_name(name)
    first = name[name.rindex(" ")..-1]
    last = name[0...name.rindex(" ")]

    return first, name
  end

  def self.ensure_unique_username(original_username)

    username_with_counter = nil

    counter = 1

    while User.where(:username => (username_with_counter || original_username)).exists?
      username_with_counter = "#{original_username}#{counter}"
      logger.info "Trying another username: #{username_with_counter} for new user"
      counter += 1
    end

    username_with_counter || original_username
  end

end
