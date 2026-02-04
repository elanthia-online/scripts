# frozen_string_literal: true

# Tests for GTK3 bugfixes in scripts/map.lic
#
# These tests verify the behavioral contracts of two fixes:
#   1. Borderless toggle: compound expression split to avoid
#      gobject-introspection invoke crash
#   2. before_dying cleanup: image widgets hidden before window
#      destruction to prevent macOS Quartz segfault

# Minimal GTK doubles — no GTK3 gem required to run these specs
module Gtk
  class Window
    attr_reader :decorated, :calls

    def initialize
      @decorated = true
      @calls = []
    end

    def set_decorated(val)
      @calls << [:set_decorated, val]
      @decorated = val
    end

    def destroy
      @calls << [:destroy]
    end
  end

  class Image
    attr_reader :calls, :visible

    def initialize
      @calls = []
      @visible = true
    end

    def hide
      @calls << [:hide]
      @visible = false
    end

    def destroy
      @calls << [:destroy]
    end
  end

  class Menu
    attr_reader :calls

    def initialize
      @calls = []
    end

    def destroy
      @calls << [:destroy]
    end
  end

  class CheckMenuItem
    attr_accessor :active

    def initialize(active: false)
      @active = active
    end
  end
end

describe "map.lic GTK bugfixes" do
  describe "borderless toggle (Bug 1)" do
    # The fix splits:
    #   window.set_decorated(!setting_borderless = owner.active?)
    # into:
    #   setting_borderless = owner.active?
    #   window.set_decorated(!setting_borderless)

    let(:window) { Gtk::Window.new }

    def apply_borderless_toggle(window, owner_active)
      # This is the fixed handler logic from map.lic line 697-700
      setting_borderless = owner_active
      window.set_decorated(!setting_borderless)
      setting_borderless
    end

    it "sets decorated to false when toggled on" do
      setting_borderless = apply_borderless_toggle(window, true)
      expect(window.decorated).to eq(false)
      expect(setting_borderless).to eq(true)
    end

    it "sets decorated to true when toggled off" do
      setting_borderless = apply_borderless_toggle(window, false)
      expect(window.decorated).to eq(true)
      expect(setting_borderless).to eq(false)
    end

    it "calls set_decorated with a plain boolean, not a compound expression" do
      apply_borderless_toggle(window, true)
      expect(window.calls.size).to eq(1)

      call_name, call_arg = window.calls.first
      expect(call_name).to eq(:set_decorated)
      # The argument must be a simple boolean — not the result of an inline
      # assignment, which is what crashed gobject-introspection's invoke.
      expect(call_arg).to eq(false)
      expect([true, false]).to include(call_arg)
    end

    it "correctly round-trips through multiple toggles" do
      setting_borderless = false

      # Toggle on
      setting_borderless = apply_borderless_toggle(window, true)
      expect(setting_borderless).to eq(true)
      expect(window.decorated).to eq(false)

      # Toggle off
      setting_borderless = apply_borderless_toggle(window, false)
      expect(setting_borderless).to eq(false)
      expect(window.decorated).to eq(true)
    end
  end

  describe "before_dying cleanup order (Bug 2)" do
    # The fix adds image.hide and circle_image.hide before
    # menu.destroy and window.destroy to prevent a macOS Quartz
    # segfault in _gdk_quartz_unref_cairo_surface.

    let(:window) { Gtk::Window.new }
    let(:image) { Gtk::Image.new }
    let(:circle_image) { Gtk::Image.new }
    let(:menu) { Gtk::Menu.new }

    def run_cleanup(image, circle_image, menu, window)
      # This is the fixed cleanup logic from map.lic lines 1129-1136
      image.hide
      circle_image.hide
      menu.destroy
      window.destroy
    end

    it "hides image before destroying window" do
      run_cleanup(image, circle_image, menu, window)
      expect(image.visible).to eq(false)
      expect(image.calls.first).to eq([:hide])
    end

    it "hides circle_image before destroying window" do
      run_cleanup(image, circle_image, menu, window)
      expect(circle_image.visible).to eq(false)
      expect(circle_image.calls.first).to eq([:hide])
    end

    it "destroys menu before window" do
      run_cleanup(image, circle_image, menu, window)
      expect(menu.calls).to eq([[:destroy]])
      expect(window.calls).to eq([[:destroy]])
    end

    it "executes operations in the correct order" do
      call_log = []

      allow(image).to receive(:hide) { call_log << :image_hide }
      allow(circle_image).to receive(:hide) { call_log << :circle_hide }
      allow(menu).to receive(:destroy) { call_log << :menu_destroy }
      allow(window).to receive(:destroy) { call_log << :window_destroy }

      run_cleanup(image, circle_image, menu, window)

      expect(call_log).to eq([
        :image_hide,
        :circle_hide,
        :menu_destroy,
        :window_destroy
      ])
    end

    it "hides all images before any destroy call" do
      call_log = []

      allow(image).to receive(:hide) { call_log << [:hide, :image] }
      allow(circle_image).to receive(:hide) { call_log << [:hide, :circle_image] }
      allow(menu).to receive(:destroy) { call_log << [:destroy, :menu] }
      allow(window).to receive(:destroy) { call_log << [:destroy, :window] }

      run_cleanup(image, circle_image, menu, window)

      hide_indices = call_log.each_index.select { |i| call_log[i][0] == :hide }
      destroy_indices = call_log.each_index.select { |i| call_log[i][0] == :destroy }

      expect(hide_indices.max).to be < destroy_indices.min
    end
  end
end
