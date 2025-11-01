WITH hs_tnt_items AS (
  -- Find the itemid(s) corresponding to high-sensitivity Troponin-T
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
    AND LOWER(label) LIKE '%high sensitivity%'
),
first_hs_tnt AS (
  -- For each admission, grab the very first hs-TnT measurement
  SELECT
    subject_id,
    hadm_id,
    valuenum      AS initial_val,
    charttime
  FROM (
    SELECT
      le.subject_id,
      le.hadm_id,
      le.valuenum,
      le.charttime,
      ROW_NUMBER() OVER(PARTITION BY le.subject_id, le.hadm_id
                        ORDER BY le.charttime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN hs_tnt_items h
      ON le.itemid = h.itemid
    WHERE le.valuenum IS NOT NULL
  )
  WHERE rn = 1
),
cohort AS (
  -- Restrict to males 50–60 with chest pain or AMI and initial hs-TnT > 0.014
  SELECT
    f.subject_id,
    f.hadm_id,
    f.initial_val
  FROM first_hs_tnt f
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f.subject_id = a.subject_id
   AND f.hadm_id   = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id
   AND a.hadm_id   = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code    = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND f.initial_val > 0.014
    AND (
         LOWER(d.long_title) LIKE '%chest pain%'
      OR LOWER(d.long_title) LIKE '%myocardial infarction%'
    )
),
quartiles AS (
  -- Compute quartiles of the initial hs-TnT values
  SELECT
    APPROX_QUANTILES(initial_val, 4) AS qt
  FROM cohort
),
metrics AS (
  -- Compute patient/admission counts and mean
  SELECT
    COUNT(DISTINCT subject_id) AS patient_count,
    COUNT(DISTINCT hadm_id)    AS admission_count,
    AVG(initial_val)           AS mean_hsTnT
  FROM cohort
)
-- Final aggregation: join metrics with quartiles to get median and IQR
SELECT
  m.patient_count,
  m.admission_count,
  m.mean_hsTnT,
  q.qt[OFFSET(2)]                          AS median_hsTnT,
  (q.qt[OFFSET(3)] - q.qt[OFFSET(1)])      AS iqr_hsTnT
FROM metrics m
CROSS JOIN quartiles q;