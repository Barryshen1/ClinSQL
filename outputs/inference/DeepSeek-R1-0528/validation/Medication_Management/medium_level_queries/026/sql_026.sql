WITH t2d_dx AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE REGEXP_CONTAINS(LOWER(long_title), r'type 2 diabetes|type ii diabetes')
),
hf_dx AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE REGEXP_CONTAINS(LOWER(long_title), r'heart failure')
),
cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
cohort_dx AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    c.admittime, 
    c.dischtime
  FROM cohort c
  WHERE c.age_at_admit BETWEEN 38 AND 48
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN t2d_dx ON di.icd_code = t2d_dx.icd_code 
                AND di.icd_version = t2d_dx.icd_version
    WHERE di.subject_id = c.subject_id 
      AND di.hadm_id = c.hadm_id
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN hf_dx ON di.icd_code = hf_dx.icd_code 
                AND di.icd_version = hf_dx.icd_version
    WHERE di.subject_id = c.subject_id 
      AND di.hadm_id = c.hadm_id
  )
),
insulin_events AS (
  SELECT subject_id, hadm_id, charttime AS admin_time
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE LOWER(medication) LIKE '%insulin%'
  UNION ALL
  SELECT subject_id, hadm_id, starttime AS admin_time
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE itemid IN (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items` 
    WHERE LOWER(label) LIKE '%insulin%'
  )
),
oral_events AS (
  SELECT subject_id, hadm_id, charttime AS admin_time
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE REGEXP_CONTAINS(LOWER(medication), 
    r'metformin|glipizide|glyburide|glimepiride|pioglitazone|rosiglitazone|sitagliptin|saxagliptin|linagliptin|alogliptin|repaglinide|nateglinide|acarbose|miglitol|canagliflozin|dapagliflozin|empagliflozin|ertugliflozin')
),
cohort_meds AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN i.admin_time BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS insulin_first_72h,
    MAX(CASE WHEN o.admin_time BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS oral_first_72h,
    MAX(CASE WHEN i.admin_time BETWEEN GREATEST(c.admittime, DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR)) AND c.dischtime THEN 1 ELSE 0 END) AS insulin_final_72h,
    MAX(CASE WHEN o.admin_time BETWEEN GREATEST(c.admittime, DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR)) AND c.dischtime THEN 1 ELSE 0 END) AS oral_final_72h
  FROM cohort_dx c
  LEFT JOIN insulin_events i 
    ON c.subject_id = i.subject_id 
    AND c.hadm_id = i.hadm_id  -- Fixed: Added AND here
  LEFT JOIN oral_events o 
    ON c.subject_id = o.subject_id 
    AND c.hadm_id = o.hadm_id
  GROUP BY c.subject_id, c.hadm_id
)
SELECT 
  'First 72h' AS time_window,
  COUNT(*) AS total_patients,
  ROUND(100.0 * SUM(insulin_first_72h) / COUNT(*), 2) AS percent_insulin,
  ROUND(100.0 * SUM(oral_first_72h) / COUNT(*), 2) AS percent_oral
FROM cohort_meds
UNION ALL
SELECT 
  'Final 72h' AS time_window,
  COUNT(*) AS total_patients,
  ROUND(100.0 * SUM(insulin_final_72h) / COUNT(*), 2) AS percent_insulin,
  ROUND(100.0 * SUM(oral_final_72h) / COUNT(*), 2) AS percent_oral
FROM cohort_meds;