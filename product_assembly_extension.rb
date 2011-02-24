# Uncomment this if you reference any of your controllers in activate
# require_dependency 'application'

class ProductAssemblyExtension < Spree::Extension
  version "1.0"
  description "Describe your extension here"
  url "http://yourwebsite.com/product_assembly"

  # Please use product_assembly/config/routes.rb instead for extension routes.

  def self.require_gems(config)
    #config.gem 'composite_primary_keys', :lib => false
  end

  def activate

    Variant.class_eval do
      has_and_belongs_to_many  :assemblies, :class_name => "Product",
            :join_table => "assemblies_parts",
            :foreign_key => "part_id", :association_foreign_key => "assembly_id"

      def translate_bundles_i_am_contained_within_into_taxons2
        print "ok, about to blow out " + self.name + " / " + self.permalink + " which currently has " + self.assemblies.count.to_s + " assemblies \n\r"
        assemblies.each {|a|
          #copy into the right taxons
          pt = ProductsTaxon.new(:product_id => self.product.id, :taxon_id => a.taxons[0].id, :name2 => a.name)
          pt.save
          print " added myself to taxon: " + a.taxons[0].name + "\n\r"
          print " a only has " + a.taxons.count.to_s + " taxons, good\n\r"
          print " giving myself in that taxon " + a.name + " name\n\r"

          pp = ProductProperty.find(:first,:conditions => ["property_id = ? && product_id = ?",a.properties.find_by_name("car_make"),a.id])
          make = !pp.nil? ? pp.value : ""
          pp = ProductProperty.find(:first,:conditions => ["property_id = ? && product_id = ?",a.properties.find_by_name("car_model"),a.id])
          model = !pp.nil? ? pp.value : ""
          pp = ProductProperty.find(:first,:conditions => ["property_id = ? && product_id = ?",a.properties.find_by_name("car_start_year"),a.id])
          car_start_year = !pp.nil? ? pp.value : ""
          pp = ProductProperty.find(:first,:conditions => ["property_id = ? && product_id = ?",a.properties.find_by_name("car_end_year"),a.id])
          car_end_year = !pp.nil? ? pp.value : ""
          self.hidden = false
          self.save
          c = Car.new(:make => make, :model => model, :start_year => car_start_year, :end_year => car_end_year)
          c.save
          self.product.cars << c
          #then soft delete it.
          print " now killing my assemblies \n\r"
          pk = Product.find(a.id)
          pk.deleted_at = Time.now()
          pk.save
          pk.variants.each do |v|
            v.deleted_at = Time.now()
            v.save
          end
          #and remove the assembly
           a2 = AssembliesPart.get(a.id,self.id)
           a2.destroy
        }
      end
    end

    Product.class_eval do

      has_and_belongs_to_many  :assemblies, :class_name => "Product",
            :join_table => "assemblies_parts",
            :foreign_key => "part_id", :association_foreign_key => "assembly_id"

      has_and_belongs_to_many  :parts, :class_name => "Variant",
            :join_table => "assemblies_parts",
            :foreign_key => "assembly_id", :association_foreign_key => "part_id"

        has_and_belongs_to_many  :positive_parts, :class_name => "Variant",
              :join_table => "assemblies_parts",
              :foreign_key => "assembly_id", :association_foreign_key => "part_id", :conditions => ["count > 0"]

        has_and_belongs_to_many  :negative_parts, :class_name => "Variant",
              :join_table => "assemblies_parts",
              :foreign_key => "assembly_id", :association_foreign_key => "part_id", :conditions => ["count < 0"]
              
      named_scope :individual_saled, {
        :conditions => ["products.individual_sale = ?", true]
      }       
       
       
      named_scope :nonbundles, { :conditions => [ 'assemblies_parts.assembly_id is null'], :include => :parts }
      named_scope :bundles, { :conditions => [ 'assemblies_parts.count=?', '1'], :include => :parts }
      named_scope :breakaparts,  { :conditions => [ 'assemblies_parts.count=?', '-1'], :include => :parts }
      
        
      named_scope :active, lambda { |*args|
        not_deleted.individual_saled.available(args.first).scope(:find)
      }


      
      def breakapart?
        return negative_parts.count > 0
      end

      def limiting_reactant
        if (positive_parts.size <= 0)
           return nil
        else
          first = positive_parts.sort{|x,y| x.product.on_hand <=> y.product.on_hand }[0]
          if (first.nil?)
            return nil
          else
            return first.product
          end
        end
      end

      alias_method :orig_on_hand, :on_hand
      # returns the number of inventory units "on_hand" for this product
      def on_hand
        if self.assembly?
          if self.breakapart? && self.orig_on_hand > 0
            return self.orig_on_hand 
          else
            positive_parts.map{|v| v.on_hand / self.count_of(v) }.min
          end
        elsif self.variants.count > 0
          main_var = self.variants.find(:first, :conditions => ["sku = ?",self.sku])
          !main_var.nil? ? main_var.on_hand : self.orig_on_hand
        else
          self.orig_on_hand
        end
      end

      alias_method :orig_on_hand=, :on_hand=
      def on_hand=(new_level)
        self.orig_on_hand=(new_level) unless self.assembly?
        
      end

      alias_method :orig_has_stock?, :has_stock?
      def has_stock?
        if self.assembly?
          if self.breakapart? && self.orig_on_hand > 0
            self.orig_has_stock?
          else
            !positive_parts.detect{|v| self.count_of(v) > v.product.on_hand}
          end
        else
          self.orig_has_stock?
        end
      end

      def add_part(variant, count = 1)
        ap = AssembliesPart.get(self.id, variant.id)
        #if !self.contains?([variant.product]) && !variant.product.recursive?
          unless ap.nil?
            ap.count += count
            ap.save
          else
            self.parts << variant
            set_part_count(variant, count)
          end
        #else
         # flash[:notice]= 'Cannot add a recursive product'
        #end
      end

      def remove_part(variant)
        ap = AssembliesPart.get(self.id, variant.id)
        unless ap.nil?
          ap.destroy
        end
      end

      def set_part_count(variant, count)
        ap = AssembliesPart.get(self.id, variant.id)
        unless ap.nil?
          if count == 0
            ap.destroy
          else
            ap.count = count
            ap.save
          end
        end
      end

      def assembly?
        parts.present?
      end

      def part?
        assemblies.present?
      end

      def count_of(variant)
        ap = AssembliesPart.get(self.id, variant.id)
        ap ? ap.count : 0
      end

    end

    InventoryUnit.class_eval do
      def self.sell_units(order)
        # we should not already have inventory associated with the order at this point but we should clear to be safe (#1394)
        order.inventory_units.destroy_all
        out_of_stock_items = []
        order.line_items.each do |line_item|
          variant = line_item.variant
          quantity = line_item.quantity
          product = variant.product
          if product.assembly?
            if product.breakapart? && product.orig_on_hand > 0
              out_of_stock_items += self.mark_units_as_sold(order, variant, quantity)
            else
              product.parts.each do |v|
                out_of_stock_items += self.mark_units_as_sold(order, v, quantity * product.count_of(v))
              end
            end
          else
            out_of_stock_items += self.mark_units_as_sold(order, variant, quantity)
          end
        end
        out_of_stock_items.flatten
      end

      #private

      def self.mark_units_as_sold(order, variant, quantity)
        out_of_stock_items = []
        #Force reload in case of ReadOnly and too ensure correct onhand values
        variant = Variant.find(variant.id)
        # mark all of these units as sold and associate them with this order
        remaining_quantity = variant.count_on_hand - quantity
        if (remaining_quantity >= 0)
          quantity.times do
            order.inventory_units.create(:variant => variant, :state => "sold")
          end
          variant.update_attribute(:count_on_hand, remaining_quantity)
        else
          (quantity + remaining_quantity).times do
            order.inventory_units.create(:variant => variant, :state => "sold")
          end
          if Spree::Config[:allow_backorders]
            (-remaining_quantity).times do
              order.inventory_units.create(:variant => variant, :state => "backordered")
            end
          else
            line_item.update_attribute(:quantity, quantity + remaining_quantity)
            out_of_stock_items << {:line_item => line_item, :count => -remaining_quantity}
          end     
          variant.update_attribute(:count_on_hand, 0)
        end
        out_of_stock_items
      end

    end

  end
end
