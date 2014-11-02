require 'digest/sha2'
require 'killbill_client'

KillBillClient.url = 'http://127.0.0.1:8080'
KillBillClient.username = 'admin'
KillBillClient.password = 'password'
KillBillClient.api_key = 'bob'
KillBillClient.api_secret = 'lazar'

class WelcomeController < ApplicationController
  def index
    @cc_accepted = nil
  end

  def signup
    unless params['cc_number'].nil?
      is_bad = params['cc_number'].to_i % 2 == 0

      kb_account = create_account(params)
      kb_pm = create_pm(kb_account, params)
      kb_charge = create_charge(is_bad, kb_account, params)

      if !kb_charge.nil?
        @cc_accepted = true
        render :index
      else
        @cc_accepted = false
        render :index
      end
    else
      redirect_to :root
    end
  end

  private

  CREATED_BY = 'Money2020 hackathon'

  def create_account(params)
    account = KillBillClient::Model::Account.new
    account.name = params['name']
    account.external_key = Time.now.to_i.to_s
    account.email = 'cristina.rodriguez+' + account.external_key[account.external_key.size - 4..account.external_key.size - 1] + '@killbill.io'
    account.currency = 'CLP'
    account.time_zone = 'UTC'
    account.address1 = params['address1']
    account.address2 = params['address2']
    account.postal_code = params['zip'].to_i
    account.company = nil
    account.city = params['city']
    account.state = nil
    account.country = (params['user'] || {})['country']
    account.locale = 'CL_es'
    account.is_notified_for_invoices = false
    account = account.create(CREATED_BY)

    Rails.logger.info("Create account: #{account.to_json}")

    account
  end

  def create_pm(account, params = {})
    pm = KillBillClient::Model::PaymentMethod.new
    pm.account_id = account.account_id
    pm.is_default = true
    pm.plugin_name = '__EXTERNAL_PAYMENT__'
    pm.plugin_info = {
      :last_name => account.name,
      :cc_number => params['cc_number'],
      :cc_exp_month => params['cc_exp_month'],
      :cc_exp_year => params['cc_exp_year'],
      :cc_verification_value => params['cc_verification_value']
    }

    pm = pm.create(true, CREATED_BY)

    Rails.logger.info("Create pm: #{pm.to_json}")

    pm
  end

  def create_charge(is_bad, account, params, amount=2999)
    charge = KillBillClient::Model::Transaction.new
    charge.amount = amount
    charge.currency = account.currency
    charge.payment_external_key = Time.now.to_i.to_s
    charge.transaction_external_key = Time.now.to_i.to_s

    options = {}
    # TEST MODE ONLY
    add_property('TEST_MODE', 'false', options)
    add_property('FEEDZAI_SCORE', is_bad ? '700' : '100', options)

    add_property('FEEDZAI_TRANSACTION_TYPE', 'sale', options)
    add_property('FEEDZAI_NAME', account.name, options)
    add_property('FEEDZAI_EMAIL', account.email, options)
    #add_property('FEEDZAI_USER_CREATED_AT', Time.now.to_i.to_s + '000', options)
    add_property('FEEDZAI_USER_GENDER', 'F', options)
    add_property('FEEDZAI_IP', generate_ip(is_bad), options)

    add_property('FEEDZAI_CARD_HASH', Digest::SHA512.hexdigest(params['cc_number']), options)
    add_property('FEEDZAI_CARD_FULL_NAME', params['cc_name'], options)
    add_property('FEEDZAI_CARD_EXP', params['cc_exp_month'] + '/' + (params['cc_exp_year'].to_i - 2000).to_s, options)
    add_property('FEEDZAI_CARD_COUNTRY', (params['billing'] || {})['country'], options)
    cc_number = params['cc_number'].to_s
    add_property('FEEDZAI_CARD_BIN', cc_number.slice(0, 6), options)
    add_property('FEEDZAI_CARD_LAST4', cc_number.slice(cc_number.size - 4, cc_number.size), options)

    add_property('FEEDZAI_USER_ADDRESS_LINE_1', params['address1'], options)
    add_property('FEEDZAI_USER_ADDRESS_LINE_2', params['address2'], options)
    add_property('FEEDZAI_USER_ZIP', params['zip'], options)
    add_property('FEEDZAI_USER_CITY', params['city'], options)
    add_property('FEEDZAI_USER_COUNTRY', (params['user'] || {})['country'], options)

    add_property('FEEDZAI_BILLING_ADDRESS_LINE_1', params['billing_address_1'], options)
    add_property('FEEDZAI_BILLING_ADDRESS_LINE_2', params['billing_address_2'], options)
    add_property('FEEDZAI_BILLING_ZIP', params['billing_zip'], options)
    add_property('FEEDZAI_BILLING_CITY', params['billing_city'], options)
    add_property('FEEDZAI_BILLING_REGION', params['billing_region'], options)
    add_property('FEEDZAI_BILLING_COUNTRY', (params['billing'] || {})['country'], options)

    add_property('FEEDZAI_SHIPPING_COUNTRY', is_bad ? 'CN' : 'CL', options)

    # request.user_agent
    add_property('FEEDZAI_BILLING_USER_DEFINED_USER_AGENT', 'chrome', options)
    # request.env['HTTP_ACCEPT']
    add_property('FEEDZAI_BILLING_USER_DEFINED_ACCEPT', 'application/html', options)

    charge = charge.auth(account.account_id, nil, CREATED_BY, nil, nil, options)

    Rails.logger.info("Create charge: #{charge.to_json}")

    charge
  end

  def add_property(key, value, options)
    return if value.blank?
    property = KillBillClient::Model::PluginPropertyAttributes.new
    property.key = key
    property.value = value
    options[:pluginProperty] ||= []
    options[:pluginProperty] << property
  end

  def generate_ip(is_bad)
    bad = ['58.59.68.91', '124.42.127.221', '14.220.48.253', '59.37.163.176', '61.172.238.178']
    good = ['146.83.4.145','146.83.4.146','146.83.4.147','146.83.4.148','146.83.4.149','146.83.4.150','146.83.4.151','146.83.4.152','146.83.4.153','146.83.4.154','146.83.4.155','146.83.4.156','146.83.4.157','146.83.4.158','146.83.4.159','146.83.4.160','146.83.4.161','146.83.4.162','146.83.4.163','146.83.4.164','146.83.4.165','146.83.4.166','146.83.4.167','146.83.4.168','146.83.4.169','146.83.4.170','146.83.4.171','146.83.4.172','146.83.4.173','146.83.4.174','146.83.4.175','146.83.4.176','146.83.4.177','146.83.4.178','146.83.4.179','146.83.4.180','146.83.4.181','146.83.4.182','146.83.4.183','146.83.4.184','146.83.4.185','146.83.4.186','146.83.4.187','146.83.4.188','146.83.4.189','146.83.4.190','146.83.4.191','146.83.4.192','146.83.4.193','146.83.4.194','146.83.4.195','146.83.4.196','146.83.4.197','146.83.4.198','146.83.4.199','146.83.4.200','146.83.4.201','146.83.4.202','146.83.4.203','146.83.4.204','146.83.4.205','146.83.4.206','146.83.4.207','146.83.4.208','146.83.4.209','146.83.4.210','146.83.4.211','146.83.4.212','146.83.4.213','146.83.4.214','146.83.4.215','146.83.4.216','146.83.4.217','146.83.4.218','146.83.4.219','146.83.4.220','146.83.4.221','146.83.4.222','146.83.4.223','146.83.4.224','146.83.4.225','146.83.4.226','146.83.4.227','146.83.4.228','146.83.4.229','146.83.4.230','146.83.4.231','146.83.4.232','146.83.4.233','146.83.4.234','146.83.4.235','146.83.4.236','146.83.4.237','146.83.4.238','146.83.4.239','146.83.4.240','146.83.4.241','146.83.4.242','146.83.4.243','146.83.4.244','146.83.4.245','146.83.4.246','146.83.4.247','146.83.4.248','146.83.4.249','146.83.4.250','146.83.4.251','146.83.4.252','146.83.4.253','146.83.4.254','146.83.4.255','146.83.5.0','146.83.5.1']
    is_bad ? bad.sample : good.sample
  end
end
