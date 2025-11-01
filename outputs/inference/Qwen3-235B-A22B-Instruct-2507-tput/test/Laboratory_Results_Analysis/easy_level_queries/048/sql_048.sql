WITH copd_patients AS (
  SELECT DISTINCT di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%chronic obstructive pulmonary disease%'
     OR LOWER(d.long_title) LIKE '%copd%'
     OR (di.icd_version = 10 AND di.icd_code = 'J449')
     OR (di.icd_version = 10 AND di.icd_code LIKE 'J44%')
     OR (di.icd_version = 9 AND di.icd_code = '496')
),
eligible_admissions AS (
  SELECT a.hadm_id, a.admittime, p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN copd_patients cp ON p.subject_id = cp.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) = 56
),
creatinine_measurements AS (
  SELECT le.hadm_id, le.valuenum, le.charttime, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  JOIN eligible_admissions a ON le.hadm_id = a.hadm_id
  WHERE LOWER(dli.label) LIKE '%creatinine%'
    AND LOWER(dli.fluid) = 'blood'
    AND le.valuenum IS NOT NULL
    AND le.charttime >= a.admittime
    AND le.charttime <= DATETIME_ADD(a.admittime, INTERVAL 24 HOUR)
),
avg_creatinine_per_admission AS (
  SELECT hadm_id, AVG(valuenum) AS avg_creatinine_24h
  FROM creatinine_measurements
  GROUP BY hadm_id
)
SELECT
  APPROX_QUANTILES(avg_creatinine_24h, 1000)[OFFSET(750)] AS quantile_75
FROM avg_creatinine_per_admission;