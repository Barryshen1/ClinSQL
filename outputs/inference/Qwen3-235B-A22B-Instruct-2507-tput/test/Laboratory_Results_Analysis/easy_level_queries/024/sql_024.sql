WITH sepsis_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_version = 10
    AND (
      d.icd_code LIKE 'A41%' OR 
      d.icd_code IN ('R65.20', 'R65.21')
    )
),
male_sepsis_admissions AS (
  SELECT sa.hadm_id
  FROM sepsis_admissions sa
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON sa.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
platelet_first AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON le.hadm_id = a.hadm_id
  WHERE LOWER(dli.label) = 'platelets'
    AND le.charttime >= a.admittime
    AND le.charttime <= DATETIME_ADD(a.admittime, INTERVAL 24 HOUR)
    AND le.valuenum IS NOT NULL
)
SELECT 
  STDDEV(pf.valuenum) AS platelet_count_std
FROM platelet_first pf
JOIN male_sepsis_admissions msa ON pf.hadm_id = msa.hadm_id
WHERE pf.rn = 1;