require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "manna bread" do
    [
      %{some manna bread},
      %{round of ground acorn bread},
      %{tiered honey-infused flatbread},
      %{cherry-filled loaf of dark bread},
      %{some baked thyme-dusted flatbread},
      %{dense wheat cracker studded with wheatberries},
      %{black buckwheat cracker},
      %{crispy rye cracker sprinkled with caraway seeds},
      %{flaky salted cracker dotted with tiny holes},
      %{nutty wheat cracker},
      %{some scored peppercorn flatbread},
      %{airy pale-colored teacake},
      %{stack of dark-swirled rye crisps},
      %{disk of black olive-laden bread},
      %{mushroom and potato cake},
      %{loaf of dark crusty ale bread},
      %{thick disk of golden dwarf bread},
      %{thin wafer of crispy elven waybread},
      %{small cake of golden elven waybread},
      %{some golden brown elven waybread},
      %{lemongrass biscuit},
      %{some unleavened rose-infused rice bread},
      %{petal-wrapped oatcake},
      %{garlic-laced sweet corn cake},
      %{toasted squash blossom fritter},
      %{sweet pineapple-glazed pumpkin loaf},
      %{cheese-filled manioc ball},
      %{braid of cracked wheat bread},
      %{sugar-dusted travel biscuit},
      %{filled piece of bread},
      %{thick piece of sea biscuit},
      %{greasy seal meat and oat bread},
      %{greasy willow paste bread},
      %{reddish cream-filled tart},
      %{brownish cream-filled tart},
      %{spinach-paste steamed dumpling},
      %{oblong fried dumpling},
      %{sugared barley and oat cake},
      %{sundried tomato and garlic loaf},
      %{onion and garlic-stuffed bread},
      %{thin crisp of hummus-topped bread},
      %{swirled disk of blue and yellow ground cornmeal},
      %{small wild rice and millet cake laced with maple syrup},
      %{round of fried dough branded with a charred design},
      %{wafer of candied seeds},
      %{slice of banana walnut bread},
      %{square of tart lemon cake},
      %{wedge of anise and wheat flatbread},
      %{round of garlic-rubbed bread},
      %{pancake of crispy cornbread},
      %{mini loaf of yellow cornbread},
      %{grilled flour flatbread drizzled with chile oil},
      %{flaky salted cracker dotted with tiny holes},
      %{crispy rye cracker sprinkled with caraway seeds},
      %{chewy dark brown hermit bar},
      %{pumpkin spice muffin},
      %{sugar-dusted golden doughnut},
      %{honey-laced golden spongecake},
    ].each do |manna_bread_name|
      it "recognizes #{manna_bread_name} as an manna bread" do
        manna_bread = GameObjFactory.item_from_name(manna_bread_name)
        expect(manna_bread.type).to eq "manna bread"
        expect(manna_bread.sellable).to be nil
      end
    end
  end
end
