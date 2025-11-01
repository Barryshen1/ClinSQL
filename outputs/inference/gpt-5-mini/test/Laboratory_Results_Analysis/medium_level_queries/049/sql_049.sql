WITH troponin_items AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
dataset_uln AS (
  -- 99th percentile across all Troponin T numeric measurements in the hosp labevents table
  SELECT quantiles[SAFE_OFFSET(99)] AS ul_99
  FROM (
    SELECT APPROX_QUANTILES(valuenum, 100) AS quantiles
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN troponin_items t USING(itemid)
    WHERE valuenum IS NOT NULL
  )
),
initial_tn_per_hadm AS (
  -- First Troponin T measurement (by charttime) during each hospital admission
  SELECT
    le.subject_id,
    le.hadm_id,
    a.admittime,
    le.charttime,
    le.valuenum
  FROM (
    SELECT
      le.*,
      ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn_in_adm
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN troponin_items t USING(itemid)
    -- require numeric value
    WHERE le.valuenum IS NOT NULL
      AND le.charttime IS NOT NULL
  ) le
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON le.hadm_id = a.hadm_id AND le.subject_id = a.subject_id
  WHERE le.rn_in_adm = 1
    -- ensure the lab is during the admission
    AND le.charttime >= a.admittime
    AND (a.dischtime IS NULL OR le.charttime <= a.dischtime)
),
qualifying_initials AS (
  -- Keep only male patients age 49-59 whose initial Troponin T for that admission exceeds the dataset ULN
  SELECT
    it.subject_id,
    it.hadm_id,
    it.admittime,
    it.valuenum
  FROM initial_tn_per_hadm it
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON it.subject_id = p.subject_id
  CROSS JOIN dataset_uln d     -- bring ULN into scope
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND it.valuenum > d.ul_99
),
-- Reduce to one row per subject: earliest qualifying admission per subject (so each patient counted once)
one_row_per_patient AS (
  SELECT subject_id, hadm_id, admittime, valuenum
  FROM (
    SELECT q.*,
      ROW_NUMBER() OVER (PARTITION BY q.subject_id ORDER BY q.admittime ASC) AS rn_patient
    FROM qualifying_initials q
  )
  WHERE rn_patient = 1
)
-- Final statistics: cohort size, ULN, p25, median (p50), p75, min and max
SELECT
  (SELECT COUNT(*) FROM one_row_per_patient) AS cohort_size,
  (SELECT ul_99 FROM dataset_uln) AS uln_99_dataset,
  -- compute cohort quantiles once in scalar subqueries and pick offsets
  (SELECT quantiles[SAFE_OFFSET(25)]
   FROM (SELECT APPROX_QUANTILES(valuenum, 100) AS quantiles FROM one_row_per_patient)
  ) AS p25,
  (SELECT quantiles[SAFE_OFFSET(50)]
   FROM (SELECT APPROX_QUANTILES(valuenum, 100) AS quantiles FROM one_row_per_patient)
  ) AS p50_median,
  (SELECT quantiles[SAFE_OFFSET(75)]
   FROM (SELECT APPROX_QUANTILES(valuenum, 100) AS quantiles FROM one_row_per_patient)
  ) AS p75,
  (SELECT MIN(valuenum) FROM one_row_per_patient) AS value_min,
  (SELECT MAX(valuenum) FROM one_row_per_patient) AS value_max;