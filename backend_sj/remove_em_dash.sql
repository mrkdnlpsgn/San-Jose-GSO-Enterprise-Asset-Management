-- Removes the em dash (U+2014) from text the system wrote before 2026-10-23, to match the new
-- wording ("Closed, asset back in service", "X, requested by Y"). Safe to run more than once.
-- A spaced em dash becomes ", "; any other em dash becomes a plain hyphen.
SET @d  = CONVERT(CHAR(0xE28094 USING utf8mb4) USING utf8mb4) COLLATE utf8mb4_general_ci;
SET @sd = CONCAT(' ', @d, ' ');

UPDATE asset_history      SET notes   = REPLACE(REPLACE(notes,   @sd, ', '), @d, '-') WHERE notes   LIKE CONCAT('%', @d, '%');
UPDATE audit_logs         SET details = REPLACE(REPLACE(details, @sd, ', '), @d, '-') WHERE details LIKE CONCAT('%', @d, '%');
UPDATE audit_log_digests  SET digest  = REPLACE(REPLACE(digest,  @sd, ', '), @d, '-') WHERE digest  LIKE CONCAT('%', @d, '%');
UPDATE maintenance_ledger SET findings      = REPLACE(REPLACE(findings,      @sd, ', '), @d, '-') WHERE findings      LIKE CONCAT('%', @d, '%');
UPDATE maintenance_ledger SET actions_taken = REPLACE(REPLACE(actions_taken, @sd, ', '), @d, '-') WHERE actions_taken LIKE CONCAT('%', @d, '%');
UPDATE disposal_ledger    SET reason              = REPLACE(REPLACE(reason,              @sd, ', '), @d, '-') WHERE reason              LIKE CONCAT('%', @d, '%');
UPDATE disposal_ledger    SET inspection_findings = REPLACE(REPLACE(inspection_findings, @sd, ', '), @d, '-') WHERE inspection_findings LIKE CONCAT('%', @d, '%');
UPDATE disposal_ledger    SET delete_reason       = REPLACE(REPLACE(delete_reason,       @sd, ', '), @d, '-') WHERE delete_reason       LIKE CONCAT('%', @d, '%');
UPDATE assets             SET remarks = REPLACE(REPLACE(remarks, @sd, ', '), @d, '-') WHERE remarks LIKE CONCAT('%', @d, '%');
UPDATE assets             SET description = REPLACE(REPLACE(description, @sd, ', '), @d, '-') WHERE description LIKE CONCAT('%', @d, '%');
