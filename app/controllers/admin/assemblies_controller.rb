class Admin::AssembliesController < Admin::BaseController
  helper :products
  before_filter :find_product

  def index
    @assemblies = @product.assemblies
  end

  private
    def find_product
      @product = Product.find_by_permalink(params[:product_id])
    end
end
