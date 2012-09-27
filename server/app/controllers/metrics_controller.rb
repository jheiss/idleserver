require 'intmax'
require 'set'

class MetricsController < ApplicationController
  # GET /metrics
  # GET /metrics.xml
  def index
    # Clients requesting XML get no pagination (all entries)
    # FIXME: stream results to XML clients
    per_page = Metric.per_page # will_paginate's default value
    respond_to do |format|
      format.html {}
      format.xml { per_page = Integer::MAX }
    end
    
    @q = Metric.search(params[:q])
    @metrics = @q.result.paginate(:page => params[:page], :per_page => per_page)
    
    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @metrics }
    end
  end

  # GET /metrics/1
  # GET /metrics/1.xml
  def show
    @metric = Metric.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @metric }
    end
  end

  # GET /metrics/new
  # GET /metrics/new.xml
  def new
    @metric = Metric.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @metric }
    end
  end

  # GET /metrics/1/edit
  def edit
    @metric = Metric.find(params[:id])
  end

  # POST /metrics
  # POST /metrics.xml
  def create
    @metric = Metric.new(params[:metric])

    respond_to do |format|
      if @metric.save
        flash[:notice] = 'Metric was successfully created.'
        format.html { redirect_to(@metric) }
        format.xml  { render :xml => @metric, :status => :created, :location => @metric }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @metric.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /metrics/1
  # PUT /metrics/1.xml
  def update
    @metric = Metric.find(params[:id])

    respond_to do |format|
      if @metric.update_attributes(params[:metric])
        flash[:notice] = 'Metric was successfully updated.'
        format.html { redirect_to(@metric) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @metric.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /metrics/1
  # DELETE /metrics/1.xml
  def destroy
    @metric = Metric.find(params[:id])
    @metric.destroy

    respond_to do |format|
      format.html { redirect_to(metrics_url) }
      format.xml  { head :ok }
    end
  end
  
  # Produce a report of processes that were not excluded by clients, allowing
  # admins to easily spot processes that should be added to their process
  # filter.
  def process_report
    @process_counts = {}
    Metric.where(name: 'processes').each do |metric|
      metric.message.split("\n").each do |line|
        user, pid, cputime, comm = line.split(' ')
        # Exclusion is done by the combination of user name and command name
        # in the client, so we need to count processes the same way here.
        # Use a hash to eliminate dups.  I.e. if user joebob has four bash
        # processes on a box we only want to save that client_id once.
        key = {user: user, command: comm}
        @process_counts[key] ||= Set.new
        @process_counts[key].add(metric.client)
      end
    end
  end
end
