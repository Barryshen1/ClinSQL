WITH rr_items AS (
  -- identify itemids likely corresponding to respiratory rate
  SELECT itemid, label, abbreviation
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(COALESCE(label, '')) LIKE '%respir%'
     OR LOWER(COALESCE(abbreviation, '')) LIKE '%resp%'
),

rr_events AS (
  -- respiratory rate events with numeric values
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    CAST(ce.valuenum AS FLOAT64) AS valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN rr_items di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
),

first_rr_per_stay AS (
  -- pick the first (earliest) respiratory rate per ICU stay
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    valuenum
  FROM (
    SELECT
      re.*,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id, stay_id ORDER BY charttime ASC) AS rn
    FROM rr_events re
  )
  WHERE rn = 1
),

cohort_first_rr AS (
  -- restrict to ICU stays for male patients aged 51-61 (anchor_age)
  SELECT f.*
  FROM first_rr_per_stay f
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON f.subject_id = icu.subject_id
   AND f.hadm_id = icu.hadm_id
   AND f.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON f.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
)

SELECT
  COUNT(*) AS n_stays,
  AVG(valuenum) AS mean_first_rr,
  STDDEV_SAMP(valuenum) AS sd_first_rr
FROM cohort_first_rr;