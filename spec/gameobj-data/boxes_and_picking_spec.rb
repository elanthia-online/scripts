require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "boxes" do
    box_nouns = %w[box chest coffer strongbox trunk]
    box_metals = %w[brass gold iron mithril silver steel]
    box_woods = %w[fel haon maoral modwir monir tanik thanot wooden]

    metal_descriptions = [
      %{acid-pitted},
      %{badly damaged},
      %{battered},
      %{corroded},
      %{dented},
      %{engraved},
      %{enruned},
      %{plain},
      %{scratched},
      %{sturdy},
    ]

    wood_descriptions = [
      %{badly damaged},
      %{engraved},
      %{enruned},
      %{iron-bound},
      %{plain},
      %{rotting},
      %{scratched},
      %{simple},
      %{sturdy},
      %{weathered},
    ]

    wooden_boxes = box_nouns.product(box_woods, wood_descriptions)
    metal_boxes = box_nouns.product(box_metals, metal_descriptions)

    (wooden_boxes + metal_boxes).each do |noun, material, desc|
      full_box_description = "#{desc} #{material} #{noun}"

      it "recognizes #{full_box_description} as a box" do
        box = GameObjFactory.item_from_name(full_box_description)
        expect(box.type).to eq "box"
      end

    end

    short_box_descriptions = box_nouns.product(box_woods) + box_nouns.product(box_metals)
    short_box_descriptions.each do |noun, material|
      short_box_description = "#{material} #{noun}"

      it "recognizes #{short_box_description} as a box" do
        box = GameObjFactory.item_from_name(short_box_description)
        expect(box.type).to eq "box"
      end

      phased_box_description = "shifting #{short_box_description}"

      it "recognizes #{phased_box_description} as a phased box" do
        box = GameObjFactory.item_from_name(phased_box_description)
        expect(box.type).to eq "box"
      end
    end

    describe "things that are not boxes" do
      [
        %{polished modwir box},
      ].each do |box_desc|
        it "recognizes #{box_desc} is NOT a box" do
          box = GameObjFactory.item_from_name(box_desc)
          expect(box.type.to_s).to_not include "box"
        end
      end
    end
  end

  describe "lockpicks" do
    [
      %{bone-handled dark invar lockpick},
      %{cerulean-hued wavy glaes lockpick},
      %{crystal-inset red copper lockpick},
      %{garnet-inset rose gold lockpick},
      %{gold lockpick},
      %{kelyn-tipped myklian scale lockpick},
      %{opalescent ora lockpick},
      %{pearl-etched thin alum lockpick},
      %{quartz-inlaid blued steel lockpick},
      %{ruby-edged dark mithril lockpick},
      %{sapphire brushed rolaren lockpick},
      %{straightened steel spring},
      %{tarnished silver coffin nail},
      %{rust-colored laje spoke},
    ].each do |lockpick_name|
      it "recognizes #{lockpick_name} as a lockpick" do
        box = GameObjFactory.item_from_name(lockpick_name)
        expect(box.type).to include "lockpick"
        expect(box.type).to_not include "skin"
        expect(box.type).to_not include "junk"
      end
    end
  end

  describe "lm tools" do
    [
      %{superior wooden wedge},
      %{strong wooden wedge},
      %{solid wooden wedge},
      %{warped wooden wedge},
      %{thin wooden wedge},
      %{brittle wooden wedge},

      %{lock assembly},

      %{set of professional calipers},
      %{pair of slender vaalin calipers},
    ].each do |lm_tool_name|
      it "recognizes #{lm_tool_name} as an lm tool" do
        lm_tool = GameObjFactory.item_from_name(lm_tool_name)
        expect(lm_tool.type).to include "lm tool"
      end
    end
  end

  describe "lm traps" do
    describe "sellable at the pawnshop" do
      [
        %{pair of small steel jaws},
        %{slender steel needle},

        %{green-tinted vial},
        %{thick glass vial},
        %{clear glass vial},
      ].each do |lm_trap_name|
        it "recognizes #{lm_trap_name} as an lm trap" do
          lm_trap = GameObjFactory.item_from_name(lm_trap_name)
          expect(lm_trap.type).to include "lm trap"
          expect(lm_trap.type).to_not include "magic"
          expect(lm_trap.type).to_not include "skin"
        end

        it "recognizes #{lm_trap_name} as sellable at the pawnshop" do
          lm_trap = GameObjFactory.item_from_name(lm_trap_name)
          expect(lm_trap.sellable).to eq "pawnshop"
        end
      end
    end

    describe "sellable at the gemshop" do
      [
        %{dark crystal},

        %{amethyst sphere},
        %{dark red sphere},
        %{emerald sphere},
        %{icy blue sphere},
        %{light violet sphere},
        %{reddish-brown sphere},
        %{stone grey sphere},
        %{wavering sphere},
      ].each do |lm_trap_name|
        it "recognizes #{lm_trap_name} as an lm trap" do
          lm_trap = GameObjFactory.item_from_name(lm_trap_name)
          expect(lm_trap.type).to include "lm trap"
          expect(lm_trap.type).to include "magic"
        end

        it "recognizes #{lm_trap_name} as sellable at the gemshop" do
          lm_trap = GameObjFactory.item_from_name(lm_trap_name)
          expect(lm_trap.sellable).to eq "gemshop"
        end
      end
    end
  end
end
