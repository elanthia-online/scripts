require_relative "./helper.rb"

describe Migration::Table do
  describe "exlcusion rules" do
    before { 
      @table = Migration::Table.from_yaml(Helper::Mocks.table_path(:exclusions))
    }

    it "creates a valid Regexp" do
      compiled_table = @table.to_regex
      expect(compiled_table).to have_key(:exclude)
      expect(%[fox]).to match(compiled_table.fetch(:exclude))
      expect(%[lox]).not_to match(compiled_table.fetch(:exclude))
    end
  end
end
