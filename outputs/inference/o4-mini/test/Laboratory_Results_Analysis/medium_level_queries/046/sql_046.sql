WITH troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
all_trop_values AS (
  SELECT le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items di
    ON le.itemid = di.itemid
  WHERE le.valuenum IS NOT NULL
),
trop_threshold AS (
  -- Compute the 99th percentile across all troponin T measurements
  SELECT
    APPROX_QUANTILES(valuenum, 100)[OFFSET(99)] AS p99
  FROM all_trop_values
),
first_trop AS (
  -- Grab the earliest troponin T measurement per hospital admission
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum AS trop_value,
    le.charttime,
    ROW_NUMBER() OVER(PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items di
    ON le.itemid = di.itemid
  WHERE le.valuenum IS NOT NULL
),
first_trop_per_adm AS (
  SELECT subject_id, hadm_id, trop_value
  FROM first_trop
  WHERE rn = 1
),
ami_admissions AS (
  -- Identify admissions with AMI or chest pain diagnoses
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%myocardial infarction%'
     OR LOWER(dd.long_title) LIKE '%chest pain%'
),
cohort AS (
  -- Assemble the cohort with filters on gender, age, AMI, and troponin > 99th percentile
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    ft.trop_value
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN ami_admissions ami
    ON a.subject_id = ami.subject_id
   AND a.hadm_id = ami.hadm_id
  JOIN first_trop_per_adm ft
    ON a.subject_id = ft.subject_id
   AND a.hadm_id = ft.hadm_id
  CROSS JOIN trop_threshold tt
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND ft.trop_value > tt.p99
)
SELECT
  COUNT(*)                                AS N,
  ROUND(AVG(anchor_age), 2)              AS mean_age,
  ROUND(AVG(los_days), 2)                AS mean_LOS_days,
  ROUND(MIN(trop_value), 3)              AS min_troponin,
  ROUND(APPROX_QUANTILES(trop_value, 2)[OFFSET(1)], 3)  AS median_troponin,
  ROUND(APPROX_QUANTILES(trop_value, 4)[OFFSET(2)], 3)  AS p75_troponin,
  ROUND(APPROX_QUANTILES(trop_value,10)[OFFSET(8)], 3)  AS p90_troponin,
  ROUND(APPROX_QUANTILES(trop_value,100)[OFFSET(98)], 3) AS p99_troponin,
  ROUND(MAX(trop_value), 3)              AS max_troponin,
  ROUND(AVG(trop_value), 3)              AS mean_troponin
FROM cohort;