WITH sepsis_hadms AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE (
    (di.icd_version = CAST('9' AS INT64) AND (
      di.icd_code LIKE 'A41%' OR 
      di.icd_code LIKE '038%' OR 
      di.icd_code = '78552'
    )) OR
    (di.icd_version = CAST('10' AS INT64) AND (
      di.icd_code LIKE 'A40%' OR 
      di.icd_code LIKE 'A41%'
    ))
  )
  AND di.seq_num = 1
),
creatinine_itemids AS (
  SELECT DISTINCT li.itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` li
  WHERE LOWER(li.label) LIKE '%creatinine%' 
    AND li.category = 'Chemistry'
    AND LOWER(li.fluid) LIKE '%blood%'
)
SELECT MAX(le.valuenum) AS max_admission_creatinine
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN sepsis_hadms sh
  ON a.hadm_id = sh.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON a.hadm_id = le.hadm_id
INNER JOIN creatinine_itemids ci
  ON le.itemid = ci.itemid
WHERE p.gender = 'M'
  AND a.hospital_expire_flag = 0
  AND le.valuenum IS NOT NULL
  AND le.valuenum > 0
  AND le.valueuom = 'mg/dL'
  AND le.charttime >= a.admittime
  AND le.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY);