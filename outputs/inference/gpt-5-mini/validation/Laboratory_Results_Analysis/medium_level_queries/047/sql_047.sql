WITH troponin_items AS (
  -- Identify Troponin T related lab itemids by label (avoid referencing loinc_code which may not exist)
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
     OR LOWER(label) LIKE '%trop t%'
     OR LOWER(label) LIKE '%troponin, t%'
),
troponin_labs AS (
  -- All Troponin T lab measurements with numeric values
  SELECT
    le.labevent_id,
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  WHERE le.itemid IN (SELECT itemid FROM troponin_items)
    AND le.valuenum IS NOT NULL
),
initial_troponin AS (
  -- First (initial) Troponin T per hospital admission
  SELECT
    subject_id,
    hadm_id,
    val AS initial_val
  FROM (
    SELECT
      tl.subject_id,
      tl.hadm_id,
      tl.valuenum AS val,
      tl.charttime,
      tl.labevent_id,
      ROW_NUMBER() OVER (PARTITION BY tl.hadm_id ORDER BY tl.charttime ASC, tl.labevent_id ASC) AS rn
    FROM troponin_labs tl
  )
  WHERE rn = 1
),
acs_admissions AS (
  -- Admissions with any diagnosis matching ACS-like descriptions
  SELECT DISTINCT d.hadm_id, d.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE LOWER(dicd.long_title) LIKE '%acute coronary%'
     OR LOWER(dicd.long_title) LIKE '%myocardial infarction%'
     OR LOWER(dicd.long_title) LIKE '%unstable angina%'
     OR LOWER(dicd.long_title) LIKE '%stemi%'
     OR LOWER(dicd.long_title) LIKE '%nstemi%'
),
patients_67_77_female AS (
  -- Female patients in the requested age window
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 67 AND 77
),
initial_all AS (
  -- All initial troponin values (used to compute 99th percentile threshold)
  SELECT initial_val
  FROM initial_troponin
  WHERE initial_val IS NOT NULL
),
threshold_99 AS (
  -- Approximate 99th percentile of initial troponin across all admissions with an initial value
  SELECT APPROX_QUANTILES(initial_val, 100)[OFFSET(99)] AS val_99
  FROM initial_all
),
cohort_candidates AS (
  -- Admissions that meet: female age 67-77 AND ACS diagnosis AND have an initial troponin
  SELECT a.hadm_id, a.subject_id, it.initial_val
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients_67_77_female p ON a.subject_id = p.subject_id
  JOIN acs_admissions acs ON a.hadm_id = acs.hadm_id AND a.subject_id = acs.subject_id
  JOIN initial_troponin it ON a.hadm_id = it.hadm_id
),
filtered_cohort AS (
  -- Filter to those with initial troponin > 99th percentile threshold
  SELECT cc.*
  FROM cohort_candidates cc
  CROSS JOIN threshold_99 t
  WHERE cc.initial_val > t.val_99
),
quartiles AS (
  -- Compute quantiles on the filtered cohort once
  SELECT APPROX_QUANTILES(initial_val, 100) AS q
  FROM filtered_cohort
)
SELECT
  (SELECT COUNT(DISTINCT subject_id) FROM filtered_cohort)                   AS patient_count,
  (SELECT COUNT(DISTINCT hadm_id)    FROM filtered_cohort)                   AS admission_count,
  (SELECT AVG(initial_val)           FROM filtered_cohort)                   AS mean_initial_troponin,
  -- median (approx) and IQR (Q3 - Q1) from APPROX_QUANTILES
  (SELECT q[OFFSET(50)] FROM quartiles)                                      AS median_initial_troponin,
  ( (SELECT q[OFFSET(75)] FROM quartiles) - (SELECT q[OFFSET(25)] FROM quartiles) ) AS iqr_initial_troponin;