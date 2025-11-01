WITH dbp_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%diastolic%'
    AND LOWER(label) LIKE '%blood pressure%'
    AND unitname = 'mmHg'
),
per_stay_max AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    MAX(ce.valuenum) AS max_dbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN dbp_itemids di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
  GROUP BY ce.subject_id, ce.hadm_id, ce.stay_id
),
cohort AS (
  SELECT
    psmax.stay_id,
    psmax.max_dbp
  FROM per_stay_max psmax
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON psmax.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON psmax.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
)
SELECT
  PERCENTILE_CONT(max_dbp, 0.5) OVER() AS median_max_dbp
FROM cohort
LIMIT 1;