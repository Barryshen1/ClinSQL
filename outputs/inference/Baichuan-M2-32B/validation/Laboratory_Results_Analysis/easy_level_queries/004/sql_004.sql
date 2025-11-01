WITH sepsis_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10
    AND (long_title LIKE '%sepsis%' OR long_title LIKE '%septic%')
),
cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    TIMESTAMP_DIFF(a.admittime, TIMESTAMP(p.anchor_year - p.anchor_age || '-01-01'), YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN sepsis_codes s ON d.icd_code = s.icd_code
  WHERE p.gender = 'F'
    AND TIMESTAMP_DIFF(a.admittime, TIMESTAMP(p.anchor_year - p.anchor_age || '-01-01'), YEAR) BETWEEN 76 AND 77
    AND d.icd_version = 10
),
platelet_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE category = 'Hematology'
    AND label LIKE '%platelet%'
    AND valueuom = '10^3/uL'
),
platelet_labs AS (
  SELECT 
    l.hadm_id,
    AVG(l.valuenum) AS avg_platelet
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN platelet_itemids p ON l.itemid = p.itemid
  WHERE l.charttime BETWEEN l.admittime AND l.admittime + INTERVAL 24 HOUR
    AND l.valuenum IS NOT NULL
  GROUP BY l.hadm_id
)
SELECT 
  APPROX_QUANTILES(avg_platelet, 100)[OFFSET(50)] AS median_platelet
FROM cohort c
JOIN platelet_labs p ON c.hadm_id = p.hadm_id;