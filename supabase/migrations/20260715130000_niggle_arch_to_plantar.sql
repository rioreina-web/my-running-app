-- §4 niggle vocabulary unification (drift audit 2026-07-15).
--
-- The canonical body-area key for the plantar/arch region changed from `arch`
-- to `plantar` in _shared/bodyVocabulary.ts, to match the iOS BodyArea enum's
-- `plantar` case. Previously the backend stored `arch` (with "plantar" as a
-- synonym) while iOS's canonical case was `plantar` with no `arch`, so a
-- memo-pipeline niggle stored as `arch` failed BodyArea(rawValue:) on iOS —
-- the round trip was broken in both directions.
--
-- Migrate any stored `arch` rows to `plantar`. body_area lives in three tables;
-- the UPDATE is a no-op where no `arch` rows exist. Idempotent.

update body_mentions      set body_area = 'plantar' where body_area = 'arch';
update injuries           set body_area = 'plantar' where body_area = 'arch';
update niggle_resolutions set body_area = 'plantar' where body_area = 'arch';
