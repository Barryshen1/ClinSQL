WITH heart_failure_icds AS (
  -- Get ICD codes for heart failure (ICD-9: 428.*, ICD-10: I50.*)
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '428%')
    OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
hf_admissions AS (
  -- Admissions with heart failure diagnosis
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN heart_failure_icds icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
),
male_66_patients AS (
  -- Male patients aged 66
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age = 66
),
target_admissions AS (
  -- Admissions for male 66yo patients with HF
  SELECT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN male_66_patients p ON a.subject_id = p.subject_id
  INNER JOIN hf_admissions hf ON a.subject_id = hf.subject_id AND a.hadm_id = hf.hadm_id
),
creatinine_itemids AS (
  -- Serum creatinine itemids
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%' AND LOWER(fluid) = 'serum'
),
creatinine_24h AS (
  -- Creatinine labs in first 24h of admission
  SELECT
    ta.subject_id,
    ta.hadm_id,
    ta.admittime,
    le.charttime,
    le.valuenum
  FROM target_admissions ta
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ta.subject_id = le.subject_id AND ta.hadm_id = le.hadm_id
  INNER JOIN creatinine_itemids ci ON le.itemid = ci.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.charttime >= ta.admittime
    AND le.charttime < DATETIME_ADD(ta.admittime, INTERVAL 24 HOUR)
)
SELECT
  subject_id,
  hadm_id,
  admittime,
  MAX(valuenum) AS max_creatinine_24h
FROM creatinine_24h
GROUP BY subject_id, hadm_id, admittime
ORDER BY admittime;