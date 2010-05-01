require 'test_helper'

class MetricsControllerTest < ActionController::TestCase
  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:metrics)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create metric" do
    assert_difference('Metric.count') do
      post :create, :metric => { }
    end

    assert_redirected_to metric_path(assigns(:metric))
  end

  test "should show metric" do
    get :show, :id => metrics(:one).to_param
    assert_response :success
  end

  test "should get edit" do
    get :edit, :id => metrics(:one).to_param
    assert_response :success
  end

  test "should update metric" do
    put :update, :id => metrics(:one).to_param, :metric => { }
    assert_redirected_to metric_path(assigns(:metric))
  end

  test "should destroy metric" do
    assert_difference('Metric.count', -1) do
      delete :destroy, :id => metrics(:one).to_param
    end

    assert_redirected_to metrics_path
  end
end
