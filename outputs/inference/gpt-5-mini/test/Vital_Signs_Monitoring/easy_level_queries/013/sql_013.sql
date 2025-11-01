SELECT
  MIN(ce.valuenum) AS min_heart_rate_bpm
FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON ce.subject_id = icu.subject_id
  AND ce.stay_id = icu.stay_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON ce.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
  ON ce.itemid = di.itemid
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 44 AND 54
  AND ce.valuenum IS NOT NULL
  -- within first 24 hours of ICU stay
  AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  -- identify heart rate / pulse items by label or abbreviation
  AND (
    REGEXP_CONTAINS(LOWER(COALESCE(di.label, '')), r'heart.*rate')
    OR REGEXP_CONTAINS(LOWER(COALESCE(di.label, '')), r'\bpulse\b')
    OR REGEXP_CONTAINS(LOWER(COALESCE(di.abbreviation, '')), r'\bhr\b')
  )
;