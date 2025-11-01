WITH acs_admissions AS (
  -- Identify admissions with ACS diagnosis for females aged 67-77
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND (
      -- ICD-10 ACS codes
      (d.icd_version = 10 AND (
        LEFT(d.icd_code,3) IN ('I20','I21','I22','I23')
      ))
      -- ICD-9 ACS codes
      OR (d.icd_version = 9 AND (
        LEFT(d.icd_code,3) IN ('410','411','413')
      ))
    )
),
troponin_t_items AS (
  -- Get itemids for Troponin T
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
initial_troponin AS (
  -- Get initial Troponin T per admission
  SELECT
    l.subject_id,
    l.hadm_id,
    MIN(l.charttime) AS initial_charttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN troponin_t_items tti ON l.itemid = tti.itemid
    JOIN acs_admissions acs ON l.subject_id = acs.subject_id AND l.hadm_id = acs.hadm_id
  GROUP BY l.subject_id, l.hadm_id
),
initial_troponin_value AS (
  -- Get the value for the initial Troponin T
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum AS initial_troponin_t
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN initial_troponin it
      ON l.subject_id = it.subject_id
      AND l.hadm_id = it.hadm_id
      AND l.charttime = it.initial_charttime
    -- Only numeric values
    WHERE l.valuenum IS NOT NULL
)
SELECT
  COUNT(DISTINCT itv.subject_id) AS patient_count,
  COUNT(DISTINCT itv.hadm_id) AS admission_count,
  ROUND(AVG(itv.initial_troponin_t), 4) AS mean_initial_troponin_t,
  ROUND(APPROX_QUANTILES(itv.initial_troponin_t, 2)[OFFSET(1)], 4) AS median_initial_troponin_t,
  ROUND(APPROX_QUANTILES(itv.initial_troponin_t, 4)[OFFSET(1)], 4) AS troponin_t_q1,
  ROUND(APPROX_QUANTILES(itv.initial_troponin_t, 4)[OFFSET(3)], 4) AS troponin_t_q3,
  ROUND(APPROX_QUANTILES(itv.initial_troponin_t, 4)[OFFSET(3)] - APPROX_QUANTILES(itv.initial_troponin_t, 4)[OFFSET(1)], 4) AS troponin_t_iqr
FROM
  initial_troponin_value itv
WHERE
  itv.initial_troponin_t > 0.01;