WITH copd_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age = 50
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'J44%'
    AND d.seq_num = 1
),
sodium_labs AS (
  SELECT cp.subject_id, cp.hadm_id, le.valuenum
  FROM copd_patients cp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON cp.subject_id = a.subject_id AND cp.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON cp.subject_id = le.subject_id AND cp.hadm_id = le.hadm_id
  WHERE le.itemid = 225624  -- Serum sodium
    AND le.valuenum IS NOT NULL
    AND le.charttime >= a.admittime
    AND le.charttime <= a.dischtime
),
nadirs AS (
  SELECT subject_id, hadm_id, MIN(valuenum) AS na_min
  FROM sodium_labs
  GROUP BY subject_id, hadm_id
)
SELECT STDDEV_SAMP(na_min) AS stddev_nadir_serum_sodium
FROM nadirs;