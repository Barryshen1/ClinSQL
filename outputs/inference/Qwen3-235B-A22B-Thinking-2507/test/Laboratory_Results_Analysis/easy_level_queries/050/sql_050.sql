WITH sepsis_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code IN ('99592', '78552'))
    OR
    (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' OR icd_code LIKE 'R652%'))
),
male_admissions AS (
  SELECT a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND a.hadm_id IN (SELECT hadm_id FROM sepsis_admissions)
),
platelet_first AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  INNER JOIN male_admissions ma
    ON le.hadm_id = ma.hadm_id
  WHERE dli.label = 'Platelets'
    AND le.valuenum IS NOT NULL
    AND le.charttime >= ma.admittime
    AND le.charttime <= ma.admittime + INTERVAL '1' DAY
)
SELECT STDDEV(valuenum) AS platelet_stddev
FROM platelet_first
WHERE rn = 1;