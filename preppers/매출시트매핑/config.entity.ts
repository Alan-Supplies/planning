import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';

export type SalesSheetMappingConfigValue = SalesSheetMappingItem[];

export type SalesSheetMappingItem = {
  storeId?: number;
  jangbuName: string;
  sheetTabName: string;
};

export const SALES_SHEET_MAPPING_CONFIG = {
  namespace: 'preppers',
  key: 'sales-sheet-mappings',
} as const;

@Entity({ name: 'configs' })
@Index('uq_configs_namespace_key', ['namespace', 'key'], { unique: true })
export class ConfigEntity {
  @PrimaryGeneratedColumn('increment', {
    type: 'bigint',
    unsigned: true,
  })
  id!: string;

  @Column({
    type: 'varchar',
    length: 64,
  })
  namespace!: string;

  @Column({
    type: 'varchar',
    length: 128,
  })
  key!: string;

  @Column({
    type: 'json',
  })
  value!: unknown;

  @Column({
    type: 'varchar',
    length: 255,
    nullable: true,
  })
  description?: string | null;

  @CreateDateColumn({
    type: 'datetime',
    precision: 6,
    name: 'created_at',
  })
  createdAt!: Date;

  @UpdateDateColumn({
    type: 'datetime',
    precision: 6,
    name: 'updated_at',
  })
  updatedAt!: Date;
}
