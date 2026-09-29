-- Phase 4 - secondary indexes, applied AFTER the bulk load.
-- Building an index once over a finished table beats maintaining it per-insert.
-- Each index maps to a named analytical module (see docs/03_database_architecture.md).

USE loan_portfolio;

ALTER TABLE `bureau` ADD INDEX `ix_bureau_curr` (`SK_ID_CURR`);
ALTER TABLE `previous_application` ADD INDEX `ix_prev_curr` (`SK_ID_CURR`);
ALTER TABLE `pos_cash_balance` ADD INDEX `ix_pos_curr` (`SK_ID_CURR`);
ALTER TABLE `credit_card_balance` ADD INDEX `ix_cc_curr` (`SK_ID_CURR`);
ALTER TABLE `installments_payments` ADD INDEX `ix_inst_prev_num` (`SK_ID_PREV`,`NUM_INSTALMENT_NUMBER`);
ALTER TABLE `installments_payments` ADD INDEX `ix_inst_curr` (`SK_ID_CURR`);

ANALYZE TABLE `application`, `bureau`, `bureau_balance`, `previous_application`,
              `pos_cash_balance`, `credit_card_balance`, `installments_payments`;
