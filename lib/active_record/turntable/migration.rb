module ActiveRecord::Turntable::Migration
  extend ActiveSupport::Concern

  included do
    extend ShardDefinition
    prepend OverrideMethods
    class_attribute :target_shards, :current_shard
    ::ActiveRecord::ConnectionAdapters::AbstractAdapter.include(SchemaStatementsExt)
    ::ActiveRecord::Migration::CommandRecorder.include(CommandRecorder)
    if ActiveRecord::Turntable::Util.ar52_or_later?
      ::ActiveRecord::MigrationContext.prepend(MigrationContext)
    else
      ::ActiveRecord::Migrator.prepend(Migrator)
    end
  end

  module ShardDefinition
    def clusters(*cluster_names)
      config = ActiveRecord::Base.turntable_config["clusters"]
      cluster_names = config.keys if cluster_names.first == :all
      (self.target_shards ||= []).concat(
          cluster_names.map do |cluster_name|
            config[cluster_name]["shards"].map { |shard| shard["connection"] }
          end.flatten
      )
      (self.target_seqs ||= []).concat(
          cluster_names.map do |cluster_name|
            config[cluster_name]["seq"].values.map { |seq| seq["connection"] }
          end.flatten
      )
    end

    def shards(*connection_names)
      (self.target_shards ||= []).concat connection_names
    end
  end

  module OverrideMethods
    def announce(message)
      super("#{message} - Shard: #{current_shard}")
    end

    def exec_migration(*args)
      super(*args) if target_shard?(current_shard)
    end

    def target_shard?(shard_name)
      return false if shard_name.present? && target_shards.blank?
      shard_name.nil? or target_shards.blank? or target_shards.include?(shard_name)
    end

    def migrate(*args)
      return migrate_without_turntable(*args) if target_shards.blank?

      config = ActiveRecord::Base.configurations[ActiveRecord::Turntable::RackupFramework.env||"development"]
      shard_conf = target_shards.map { |shard| [shard, config["shards"][shard]] }.to_h
      seqs_conf = target_seqs.map { |seq| [seq, config["seq"][seq]] }.to_h

      # SHOW FULL FIELDS FROM `users` を実行してテーブルの情報を取得するためにデフォルトのデータベースも追加する
      {"master": config}.merge(shard_conf).merge(seqs_conf).each do |connection_name, database_config|
        next if database_config["database"].blank?
        ActiveRecord::Base.clear_active_connections!
        ActiveRecord::Base.establish_connection(database_config)
        ActiveRecord::Migration.current_shard = connection_name
        migrate_without_turntable(*args)
      end
      ActiveRecord::Base.establish_connection config
      ActiveRecord::Base.clear_active_connections!
    end
  end

  module SchemaStatementsExt
    def create_sequence_for(table_name, options = {})
      options = options.merge(id: false)

      # TODO: pkname should be pulled from table definitions
      sequence_table_name = ActiveRecord::Turntable::Sequencer.sequence_name(table_name, "id")
      create_table(sequence_table_name, options) do |t|
        t.integer :id, limit: 8
      end
      execute "INSERT INTO #{quote_table_name(sequence_table_name)} (`id`) VALUES (0)"
    end

    def drop_sequence_for(table_name, options = {})
      # TODO: pkname should be pulled from table definitions
      sequence_table_name = ActiveRecord::Turntable::Sequencer.sequence_name(table_name, "id")
      drop_table(sequence_table_name)
    end

    def rename_sequence_for(table_name, new_name)
      # TODO: pkname should pulled from table definitions
      seq_table_name = ActiveRecord::Turntable::Sequencer.sequence_name(table_name, "id")
      new_seq_name = ActiveRecord::Turntable::Sequencer.sequence_name(new_name, "id")
      rename_table(seq_table_name, new_seq_name)
    end
  end

  module CommandRecorder
    def create_sequence_for(*args)
      record(:create_sequence_for, args)
    end

    def rename_sequence_for(*args)
      record(:rename_sequence_for, args)
    end

    private

      def invert_create_sequence_for(args)
        [:drop_sequence_for, args]
      end

      def invert_rename_sequence_for(args)
        [:rename_sequence_for, args.reverse]
      end
  end

  module MigrationContext
    extend ActiveSupport::Concern

    def up(target_version = nil)
      result = super

      ActiveRecord::Tasks::DatabaseTasks.each_current_turntable_cluster_connected(current_environment) do |name, configuration|
        puts "[turntable] *** Migrating database: #{configuration['database']}(Shard: #{name})"
        super(target_version)
      end

      result
    end

    def down(target_version = nil)
      result = super

      ActiveRecord::Tasks::DatabaseTasks.each_current_turntable_cluster_connected(current_environment) do |name, configuration|
        puts "[turntable] *** Migrating database: #{configuration['database']}(Shard: #{name})"
        super(target_version)
      end

      result
    end

    def run(direction, target_version)
      result = super

      ActiveRecord::Tasks::DatabaseTasks.each_current_turntable_cluster_connected(current_environment) do |name, configuration|
        puts "[turntable] *** Migrating database: #{configuration['database']}(Shard: #{name})"
        super(target_version)
      end

      result
    end
  end

  module Migrator
    extend ActiveSupport::Concern

    def self.prepended(base)
      class << base
        prepend ClassMethods
      end
    end

    module ClassMethods
      def up(migrations_paths, target_version = nil)
        result = super

        ActiveRecord::Tasks::DatabaseTasks.each_current_turntable_cluster_connected(current_environment) do |name, configuration|
          puts "[turntable] *** Migrating database: #{configuration['database']}(Shard: #{name})"
          super(migrations_paths, target_version)
        end
        result
      end

      def down(migrations_paths, target_version = nil, &block)
        result = super

        ActiveRecord::Tasks::DatabaseTasks.each_current_turntable_cluster_connected(current_environment) do |name, configuration|
          puts "[turntable] *** Migrating database: #{configuration['database']}(Shard: #{name})"
          super(migrations_paths, target_version, &block)
        end
        result
      end

      def run(*args)
        result = super

        ActiveRecord::Tasks::DatabaseTasks.each_current_turntable_cluster_connected(current_environment) do |name, configuration|
          puts "[turntable] *** Migrating database: #{configuration['database']}(Shard: #{name})"
          super(*args)
        end
        result
      end
    end
  end
end
