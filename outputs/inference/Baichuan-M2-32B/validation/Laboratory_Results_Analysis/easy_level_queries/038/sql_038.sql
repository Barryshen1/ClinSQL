WITH qualifying_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    FLOOR(TIMESTAMP_DIFF(a.admittime, DATE_SUB(DATE(p.anchor_year, 1, 1), INTERVAL p.anchor_age YEAR), DAY) / 365.25) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
stroke_admissions AS (
  SELECT DISTINCT
    qa.subject_id,
    qa.hadm_id,
    qa.admittime
  FROM qualifying_admissions qa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON qa.subject_id = d.subject_id AND qa.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE dd.icd_version = 10 
    AND LOWER(dd.long_title) LIKE '%ischemic stroke%'
    AND qa.age_at_admission BETWEEN 49.5 AND 50.5
),
hemoglobin_labs AS (
  SELECT 
    le.valuenum
  FROM stroke_admissions s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON s.subject_id = le.subject_id AND s.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li 
    ON le.itemid = li.itemid
  WHERE le.charttime BETWEEN s.admittime 
    AND TIMESTAMP_ADD(s.admittime, INTERVAL 24 HOUR)
    AND (LOWER(li.label) LIKE '%hemoglobin%' OR LOWER(li.label) LIKE '%hgb%')
    AND le.valuenum IS NOT NULL
)
SELECT 
  SAFE_CAST(MIN(valuenum) AS FLOAT64) AS min_hemoglobin
FROM hemoglobin_labs;