# frozen_string_literal: true

class DeveloperController < ApplicationController
  before_action :authenticate_user!, except: [:blank_page]
  before_action :verify_developer, except: [:blank_page, :change_back, :verify_elevation]
  before_action :check_impersonating, only: [:change_back, :verify_elevation]

  def update_sites
    SitesHelper.update_sites
    flash[:info] = 'Site cache updated, refer to MiniProfiler for execution details.'
    redirect_back(fallback_location: url_for(controller: :dashboard, action: :index))
  end

  def production_log
    @log = if params[:grep].present?
             `tail -n 10000 log/production.log | grep -E '#{params[:grep]}' -C #{params[:context]} --color=never`
           else
             `tail -n 1000 log/production.log`
           end

    # Don't modify frozen strings
    @log.gsub(/\e\[([;\d]+)?m/, '') # Terminal color codes
    @log.gsub(/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/, '') # IPs
    @log.gsub(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,4}\b/i, '') # Emails
  end

  def deploy
    message = "[ [metasmoke-deploy](//travis-ci.org/Undo1/metasmoke-deploy) ] deploy started by #{current_user.username}"
    SmokeDetector.send_message_to_charcoal(message)

    # old_message = Octokit.commit('Charcoal-SE/metasmoke', CurrentCommit)['commit']['message']
    old_sha = CurrentCommit.first(7)

    commit = Octokit.commits('Charcoal-SE/metasmoke')[0]
    message = commit['commit']['message']
    sha = commit['sha'].first(7)

    HTTParty.post('https://api.travis-ci.org/repo/19152912/requests', headers: {
                    'Content-Type' => 'application/json',
                    'Accept' => 'application/json',
                    'Travis-API-Version' => '3',
                    'Authorization' => "token #{AppConfig['travis']['token']}"
                  }, body: {
                    request: {
                      branch: 'master',
                      message: "#{old_sha} -> #{sha}: #{message}"
                    }
                  }.to_json)

    redirect_to 'https://travis-ci.org/Undo1/metasmoke-deploy'
  end

  def query_times_log
    send_file 'log/query_times.log'
  end

  def blank_page
    render layout: false
  end

  def websocket_test; end

  def send_websocket_test
    ActionCable.server.broadcast params[:channel], JSON.parse(params[:content])
    flash[:info] = 'Queued for broadcast.'
    redirect_to url_for(controller: :developer, action: :websocket_test)
  end

  def change_users
    dev_id = current_user.id
    @user = User.find params[:id]
    sign_in @user
    session[:impersonator_id] = dev_id
    flash[:success] = "You are now impersonating #{@user.username}."
    redirect_to root_path
  end

  def change_back
    @impersonator = User.find session[:impersonator_id]
  end

  def verify_elevation
    @impersonator = User.find session[:impersonator_id]
    if @impersonator&.valid_password? params[:password]
      session.delete :impersonator_id
      sign_in @impersonator
      redirect_to root_path
    else
      flash[:danger] = 'Incorrect password.'
      render :change_back
    end
  end

  def run_fcrs
    ConflictingFeedbackJob.perform_later
    flash[:success] = 'ConflictingFeedbackJob triggered.'
    redirect_back fallback_location: root_path
  end

  private

  def check_impersonating
    require_developer unless session[:impersonator_id].present?
  end
end
