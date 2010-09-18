class AssembliesPart < ActiveRecord::Base
	#set_primary_keys :assembly_id, :part_id
	belongs_to :assembly, :class_name => "Product", :foreign_key => "assembly_id"
	belongs_to :part, :class_name => "Variant", :foreign_key => "part_id"
	
	named_scope :positive, {
     :conditions => ["count > 0"]
  }
	
	def self.get(assembly_id, part_id)
	  AssembliesPart.find_by_assembly_id_and_part_id(assembly_id, part_id)
	end
	
	def save
	  AssembliesPart.update_all("count = #{count}", 
	      ["assembly_id = ? AND part_id = ?", assembly_id, part_id])
  end
  
  def destroy
    AssembliesPart.delete_all(["assembly_id = ? AND part_id = ?", assembly_id, part_id])
  end
	
end
