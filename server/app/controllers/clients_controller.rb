require 'intmax'

class ClientsController < ApplicationController
  # GET /clients
  def index
    # Clients requesting XML or CSV get no pagination (all entries)
    # FIXME: stream results to XML/CSV clients
    per_page = Client.per_page # will_paginate's default value
    respond_to do |format|
      format.html {}
      format.xml  { per_page = Integer::MAX }
      format.json { per_page = Integer::MAX }
      format.csv  { per_page = Integer::MAX }
    end
    
    @q = Client.search(params[:q])
    @clients = @q.result.paginate(:page => params[:page], :per_page => per_page)
    
    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @clients }
      format.json { render :json => @clients }
      format.csv  { @filename = 'idleserver-clients.csv' } # index.csv.csvbuilder
    end
  end

  # GET /clients/1
  def show
    @client = Client.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @client }
      format.json { render :json => @client }
    end
  end

  # GET /clients/new
  def new
    @client = Client.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @client }
      format.json { render :json => @client }
    end
  end

  # GET /clients/1/edit
  def edit
    @client = Client.find(params[:id])
  end

  # POST /clients
  def create
    @client = Client.new(params[:client])

    respond_to do |format|
      if @client.save
        flash[:notice] = 'Client was successfully created.'
        format.html { redirect_to(@client) }
        format.xml  { render :xml => @client, :status => :created, :location => @client }
        format.json { render :json => @client, :status => :created, :location => @client }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @client.errors, :status => :unprocessable_entity }
        format.json { render :json => @client.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /clients/1
  def update
    @client = Client.find(params[:id])
    
    # This forces an update of updated_at even if idleness hasn't changed. 
    # Otherwise clients will appear to go stale if their state remains
    # unchanged.
    params[:client][:updated_at] = Time.now
    
    respond_to do |format|
      if @client.update_attributes(params[:client])
        if !@client[:acknowledged_until].nil? && @client[:acknowledged_until] >= Time.now
          @client.update_attribute('idleness', 0)
        elsif !@client[:acknowledged_until].nil? && @client[:acknowledged_until] = Time.now
          @client.update_attribute('acknowledged_at', nil)
          @client.update_attribute('acknowledged_until', nil)
        end
        flash[:notice] = 'Client was successfully updated.'
        format.html { redirect_to(@client) }
        format.xml  { head :ok }
        format.json { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @client.errors, :status => :unprocessable_entity }
        format.json { render :json => @client.errors, :status => :unprocessable_entity }
      end
    end
  end

  def ack
    @client = Client.find(params[:id])
    @current_user = ""
  end

  def ackcreate
        @client = Client.find(params[:id])
        @current_user = params[:user] || ""
        if params[:user].blank? || params[:note].blank? || params[:acknowledged_until].blank?
                flash[:error] = 'All fields are compulsory.'
        else
     if @client.update_attributes(
             idleness: 0,
             acknowledged_at: Time.zone.now,
             acknowledged_until: 30.days.from_now)

             @acknowledgements = @client.acknowledgements.build(
             acknowledged_at: Time.zone.now,
             acknowledged_until: params[:acknowledged_until],
             user: @current_user,
             note: params[:note]
             )
             @acknowledgements.save
            @client.update_attributes(
            ack_count: @client.acknowledgements.count
            )
           flash[:notice] = 'Client was successfully acknowledged.'
         else
           flash[:error] = 'Acknowledgement failed.'
         end
         end
         redirect_to(@client)
 end

  # DELETE /clients/1
  # DELETE /clients/1.xml
  def destroy
    @client = Client.find(params[:id])
    @client.destroy

    respond_to do |format|
      format.html { redirect_to(clients_url) }
      format.xml  { head :ok }
      format.json { head :ok }
    end
  end
end
