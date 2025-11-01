WITH acs_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddiag
    ON diag.icd_code = ddiag.icd_code 
    AND diag.icd_version = ddiag.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 46 AND 56
    AND (ddiag.icd_code LIKE 'I21%' OR ddiag.icd_code = 'I20.0')
),
first_troponin AS (
  SELECT 
    acs.subject_id,
    acs.hadm_id,
    acs.admittime,
    acs.dischtime,
    le.charttime,
    le.flag,
    ROW_NUMBER() OVER (PARTITION BY acs.hadm_id ORDER BY le.charttime) AS rn
  FROM acs_admissions acs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON acs.subject_id = le.subject_id 
    AND acs.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.itemid = 51006  -- hs-TnT
)
SELECT 
  flag AS category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(DATE_DIFF(dischtime, admittime, DAY)), 2) AS mean_los_days
FROM first_troponin
WHERE rn = 1
  AND flag IN ('Normal', 'Borderline', 'Myocardial Injury')
GROUP BY flag
ORDER BY flag;