require 'intmax'

class ClientsController < ApplicationController
  # GET /clients
  # GET /clients.xml
  def index
    # Clients requesting XML or CSV get no pagination (all entries)
    # FIXME: stream results to XML/CSV clients
    per_page = Client.per_page # will_paginate's default value
    respond_to do |format|
      format.html {}
      format.xml { per_page = Integer::MAX }
      format.csv { per_page = Integer::MAX }
    end
    
    @q = Client.search(params[:q])
    
    # FIXME: @q.result.length is horrible.  Ransack's predecessors had a count
    # method on the query object, but ransack does not.
    if params.has_key?(:redirect_single) && @q.result.length == 1
      redirect_to client_url(@q.result.first)
      return
    end
    
    @clients = @q.result.paginate(:page => params[:page], :per_page => per_page)
    
    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @clients }
      format.csv { @filename = 'idleserver-clients.csv' } # index.csv.csvbuilder
    end
  end

  # GET /clients/1
  # GET /clients/1.xml
  def show
    @client = Client.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @client }
    end
  end

  # GET /clients/new
  # GET /clients/new.xml
  def new
    @client = Client.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @client }
    end
  end

  # GET /clients/1/edit
  def edit
    @client = Client.find(params[:id])
  end

  # POST /clients
  # POST /clients.xml
  def create
    @client = Client.new(params[:client])

    respond_to do |format|
      if @client.save
        flash[:notice] = 'Client was successfully created.'
        format.html { redirect_to(@client) }
        format.xml  { render :xml => @client, :status => :created, :location => @client }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @client.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /clients/1
  # PUT /clients/1.xml
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
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @client.errors, :status => :unprocessable_entity }
      end
    end
  end

  def ack
    @client = Client.find(params[:id])
    @client.update_attribute('idleness', 0)
    @client.update_attribute('updated_at', Time.now)
    @client.update_attribute('acknowledged_at', Time.now)
    @client.update_attribute('acknowledged_until', Time.now + 30.days)
    flash[:notice] = 'Client was successfully updated.'
    redirect_to :action => :index
  end

  # DELETE /clients/1
  # DELETE /clients/1.xml
  def destroy
    @client = Client.find(params[:id])
    @client.destroy

    respond_to do |format|
      format.html { redirect_to(clients_url) }
      format.xml  { head :ok }
    end
  end
end
