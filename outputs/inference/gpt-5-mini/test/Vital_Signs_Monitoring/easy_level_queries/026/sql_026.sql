WITH resp_items AS (
  -- Identify candidate itemids that represent respiratory rate measurements
  SELECT DISTINCT itemid, label, abbreviation
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respir%'    -- e.g. "Respiratory Rate", "Respirations"
     OR LOWER(abbreviation) LIKE '%rr%' -- e.g. abbreviation "RR"
),

rr_events AS (
  -- Pull respiratory rate events occurring in the first 24 hours of the ICU stay
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN resp_items di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
       AND ce.subject_id = icu.subject_id
       AND ce.hadm_id = icu.hadm_id
  WHERE ce.charttime IS NOT NULL
    -- first 24 hours window from ICU intime
    AND ce.charttime >= icu.intime
    AND ce.charttime <= TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
    -- numeric value present and plausible (exclude obvious erroneous values)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum <= 60
),

filtered_rr AS (
  -- Keep only patients meeting the demographic criteria (male, age 39-49)
  SELECT re.*
  FROM rr_events re
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON re.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
)

SELECT
  MIN(valuenum) AS min_respiratory_rate_first_24h,
  COUNT(DISTINCT subject_id) AS n_unique_subjects,
  COUNT(*) AS n_measurements
FROM filtered_rr;