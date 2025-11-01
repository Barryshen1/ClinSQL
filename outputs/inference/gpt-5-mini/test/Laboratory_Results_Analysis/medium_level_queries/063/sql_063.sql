WITH troponin_items AS (
  -- Troponin I itemids (case-insensitive match on label)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin i%'
),

acs_hadm AS (
  -- Admissions with an ACS-related diagnosis (text-based match on diagnosis description)
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE
    (
      LOWER(d.long_title) LIKE '%acute coronary%'
      OR LOWER(d.long_title) LIKE '%myocardial infarction%'
      OR LOWER(d.long_title) LIKE '%unstable angina%'
      OR LOWER(d.long_title) LIKE '%stemi%'
      OR LOWER(d.long_title) LIKE '%nstemi%'
    )
),

initial_troponin_events AS (
  -- All Troponin I lab events that occur during the hospital admission
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum,
    le.ref_range_upper,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items ti
    ON le.itemid = ti.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON le.hadm_id = a.hadm_id
   AND le.subject_id = a.subject_id
  WHERE
    -- ensure lab occurred during the admission window
    le.charttime BETWEEN a.admittime AND a.dischtime
    AND le.valuenum IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
),

initial_tn_per_hadm AS (
  -- Keep the earliest Troponin I per admission
  SELECT
    subject_id,
    hadm_id,
    valuenum AS initial_tn,
    ref_range_upper,
    charttime
  FROM initial_troponin_events
  WHERE rn = 1
),

cohort AS (
  -- Final cohort: ACS admissions, female, age 84-94 (or masked >89), initial troponin > ref_range_upper
  SELECT
    i.hadm_id,
    i.subject_id,
    i.initial_tn,
    i.ref_range_upper
  FROM initial_tn_per_hadm i
  JOIN acs_hadm acs
    ON i.hadm_id = acs.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON i.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    -- anchor_age is the de-identified age field in MIMIC-IV.
    -- NOTE: ages >89 may be masked (commonly encoded as 300). We include anchor_age = 300 to capture 90-94 (with caveat that 300 includes >94 as well).
    AND (p.anchor_age BETWEEN 84 AND 94 OR p.anchor_age = 300)
    AND i.initial_tn > i.ref_range_upper
),

-- Summary statistics: count and mean
agg_stats AS (
  SELECT
    COUNT(*) AS admission_count,
    AVG(initial_tn) AS mean_initial_troponin
  FROM cohort
),

-- Quantiles: approximate percentiles (0..100)
quantiles AS (
  SELECT APPROX_QUANTILES(initial_tn, 100) AS q_arr
  FROM cohort
)

SELECT
  a.admission_count,
  a.mean_initial_troponin,
  q.q_arr[OFFSET(25)] AS q1_initial_troponin,
  q.q_arr[OFFSET(50)] AS median_initial_troponin,
  q.q_arr[OFFSET(75)] AS q3_initial_troponin,
  SAFE_SUBTRACT(q.q_arr[OFFSET(75)], q.q_arr[OFFSET(25)]) AS iqr_initial_troponin
FROM agg_stats a
CROSS JOIN quantiles q;