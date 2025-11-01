WITH pneumonia_admissions AS (
  SELECT DISTINCT diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code 
    AND diag.icd_version = d_diag.icd_version
  WHERE LOWER(d_diag.long_title) LIKE '%pneumonia%'
),
cohort AS (
  SELECT 
    adm.hadm_id,
    adm.admittime,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  INNER JOIN pneumonia_admissions pneum
    ON adm.hadm_id = pneum.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) BETWEEN 45 AND 55
),
creatinine_in_24h AS (
  SELECT 
    c.hadm_id,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  INNER JOIN cohort c
    ON le.hadm_id = c.hadm_id
  WHERE 
    dli.label = 'CREATININE' 
    AND dli.fluid = 'Blood'
    AND le.valuenum IS NOT NULL
    AND le.charttime >= c.admittime
    AND le.charttime <= c.admittime + INTERVAL '24' HOUR
),
avg_creat_per_admission AS (
  SELECT 
    hadm_id,
    AVG(valuenum) AS avg_creat
  FROM creatinine_in_24h
  GROUP BY hadm_id
)
SELECT 
  STDDEV_POP(avg_creat) AS sd_avg_creat
FROM avg_creat_per_admission;