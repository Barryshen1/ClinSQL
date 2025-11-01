WITH troponin_i_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin i%'
),

-- First Troponin I measurement per hadm_id
first_troponin AS (
  SELECT
    le.hadm_id,
    le.valuenum,
    le.charttime,
    le.ref_range_upper
  FROM (
    SELECT
      le.hadm_id,
      le.charttime,
      le.valuenum,
      le.ref_range_upper,
      ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN troponin_i_items ti ON le.itemid = ti.itemid
    WHERE le.valuenum IS NOT NULL
  ) AS t
  WHERE t.rn = 1
),

-- Check if the first troponin is elevated
elevated_first_troponin AS (
  SELECT hadm_id, valuenum
  FROM first_troponin ft
  WHERE ft.valuenum > ft.ref_range_upper
),

-- Chest pain admissions
chest_pain_hadm AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dic
    ON a.subject_id = dic.subject_id AND a.hadm_id = dic.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON dic.icd_code = d.icd_code AND dic.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%chest pain%'
),

-- Age and gender filter (male, age 90-100)
age_gender_hadm AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 90 AND 100
),

-- Final cohort: hadm_ids that satisfy all conditions
cohort_hadm AS (
  SELECT e.hadm_id
  FROM elevated_first_troponin e
  JOIN chest_pain_hadm cp ON e.hadm_id = cp.hadm_id
  JOIN age_gender_hadm ag ON e.hadm_id = ag.hadm_id
),

-- Values for the final cohort
cohort_values AS (
  SELECT e.valuenum
  FROM elevated_first_troponin e
  JOIN cohort_hadm c ON e.hadm_id = c.hadm_id
)

-- Compute p25, p50, p75 and range
SELECT
  quantiles[OFFSET(25)] AS p25,
  quantiles[OFFSET(50)] AS p50,
  quantiles[OFFSET(75)] AS p75,
  min_val,
  max_val
FROM (
  SELECT quantiles
  FROM (
    SELECT APPROX_QUANTILES(valuenum, 100) AS quantiles
    FROM cohort_values
  ) AS q
) AS a
CROSS JOIN (
  SELECT MIN(valuenum) AS min_val, MAX(valuenum) AS max_val
  FROM cohort_values
) AS mv;