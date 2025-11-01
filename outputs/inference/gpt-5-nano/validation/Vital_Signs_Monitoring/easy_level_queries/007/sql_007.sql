WITH eligible_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 73 AND 83
),
admissions_with_cohort AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients e ON a.subject_id = e.subject_id
),
rr_itemids AS (
  SELECT di.itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items` di
  WHERE LOWER(di.label) LIKE '%respiratory rate%'
     OR LOWER(di.category) LIKE '%respiratory rate%'
),
rr_events AS (
  SELECT ce.subject_id, ce.hadm_id, ce.charttime, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN admissions_with_cohort awc ON ce.hadm_id = awc.hadm_id
  JOIN rr_itemids ri ON ce.itemid = ri.itemid
  WHERE ce.charttime >= awc.admittime
    AND ce.charttime <= awc.dischtime
),
first_rr_per_admission AS (
  SELECT subject_id, hadm_id, valuenum AS first_rr
  FROM (
    SELECT subject_id, hadm_id, charttime, valuenum,
           ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime) AS rn
    FROM rr_events
  )
  WHERE rn = 1
)
SELECT STDDEV_SAMP(first_rr) AS sd_first_respiratory_rate
FROM first_rr_per_admission
WHERE first_rr IS NOT NULL;