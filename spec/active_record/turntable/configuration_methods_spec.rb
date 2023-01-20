require "spec_helper"

describe ActiveRecord::Turntable::ConfigurationMethods do
  context "Define ActiveRecord::Turntable::RackupFramework" do
    subject { ActiveRecord::Turntable::RackupFramework }
    it "Support Rails" do
      is_expected.to eq(Rails)
    end
  end

  context "#turntable_configuration_file" do
    around do |example|
      old_conf_path = ActiveRecord::Base.turntable_configuration_file
      example.run
      ActiveRecord::Base.turntable_configuration_file = old_conf_path
    end

    subject { ActiveRecord::Base.turntable_configuration_file }

    let(:rackup_framework_root) { "/path/to/rackup_framework_root" }

    it "returns ActiveRecord::Turntable::RackupFramework.root/config/turntable.yml default" do
      stub_const("ActiveRecord::Turntable::RackupFramework", Class.new)
      allow(ActiveRecord::Turntable::RackupFramework).to receive(:root) { rackup_framework_root }
      ActiveRecord::Base.turntable_configuration_file = nil
      is_expected.to eq(File.join(rackup_framework_root, "config/turntable.yml"))
    end
  end

  context "#turntable_configuration" do
    subject { ActiveRecord::Base.turntable_configuration }

    it { is_expected.to be_instance_of(ActiveRecord::Turntable::Configuration) }
  end
end
