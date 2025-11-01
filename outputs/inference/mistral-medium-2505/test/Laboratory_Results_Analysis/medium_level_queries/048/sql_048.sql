WITH
-- Female patients aged 55-65
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 55 AND 65
),

-- Admissions with AMI diagnosis
ami_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM female_patients)
    AND (
      di.icd_code LIKE 'I21.%' OR
      di.icd_code LIKE 'I22.%' OR
      LOWER(di.long_title) LIKE '%myocardial infarction%'
    )
),

-- First hs-TnT > 0.01 ng/mL per admission
first_hs_tnt AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum AS hs_tnt_value,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS row_num
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON l.itemid = di.itemid
  WHERE
    l.hadm_id IN (SELECT hadm_id FROM ami_admissions)
    AND LOWER(di.label) LIKE '%hs-tnt%'
    AND l.valuenum > 0.01
),

-- Calculate percentiles
hs_tnt_percentiles AS (
  SELECT
    APPROX_QUANTILES(hs_tnt_value, 100)[OFFSET(25)] AS q1,
    APPROX_QUANTILES(hs_tnt_value, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(hs_tnt_value, 100)[OFFSET(75)] AS q3
  FROM
    first_hs_tnt
  WHERE
    row_num = 1
)

-- Final aggregation
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(hs_tnt_value) AS mean_hs_tnt,
  p.median AS median_hs_tnt,
  p.q1 AS q1_hs_tnt,
  p.q3 AS q3_hs_tnt,
  p.q3 - p.q1 AS iqr_hs_tnt
FROM
  first_hs_tnt f
CROSS JOIN
  hs_tnt_percentiles p
WHERE
  f.row_num = 1;