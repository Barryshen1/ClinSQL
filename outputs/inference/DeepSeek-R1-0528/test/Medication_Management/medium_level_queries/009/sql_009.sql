WITH diabetes_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    REGEXP_CONTAINS(LOWER(long_title), r'diabetes') AND
    NOT REGEXP_CONTAINS(LOWER(long_title), r'gestational')
),
acute_hf_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    REGEXP_CONTAINS(LOWER(long_title), r'acute (heart|cardiac) failure') OR
    REGEXP_CONTAINS(LOWER(long_title), r'acute on chronic (heart|cardiac) failure')
),
cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM (
        SELECT hadm_id, 
          MAX(IF(diag.icd_code IN (SELECT icd_code FROM diabetes_codes) AND diag.icd_version IN (SELECT icd_version FROM diabetes_codes), 1, 0)) AS diabetes,
          MAX(IF(diag.icd_code IN (SELECT icd_code FROM acute_hf_codes) AND diag.icd_version IN (SELECT icd_version FROM acute_hf_codes), 1, 0)) AS acute_hf
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        GROUP BY hadm_id
      ) t
      WHERE diabetes = 1 AND acute_hf = 1
    )
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 24
),
insulin_events AS (
  SELECT 
    subject_id, 
    hadm_id, 
    charttime, 
    medication
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE LOWER(medication) LIKE '%insulin%'
),
oral_events AS (
  SELECT 
    subject_id, 
    hadm_id, 
    charttime, 
    medication
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE 
    REGEXP_CONTAINS(LOWER(medication), r'metformin|glipizide|glyburide|glimepiride|pioglitazone|rosiglitazone|sitagliptin|saxagliptin|linagliptin|alogliptin|repaglinide|nateglinide|acarbose|miglitol|canagliflozin|dapagliflozin|empagliflozin|ertugliflozin') 
    AND LOWER(medication) NOT LIKE '%insulin%'
),
patient_flags AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    MAX(IF(
        i.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR), 
        1, 0
    )) AS insulin_first24h,
    MAX(IF(
        i.charttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime, 
        1, 0
    )) AS insulin_final24h,
    MAX(IF(
        o.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR), 
        1, 0
    )) AS oral_first24h,
    MAX(IF(
        o.charttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime, 
        1, 0
    )) AS oral_final24h
  FROM cohort c
  LEFT JOIN insulin_events i
    ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
  LEFT JOIN oral_events o
    ON c.subject_id = o.subject_id AND c.hadm_id = o.hadm_id
  GROUP BY c.subject_id, c.hadm_id
)
SELECT 
  'insulin' AS medication_type,
  ROUND(AVG(insulin_first24h) * 100, 2) AS rate_first24h,
  ROUND(AVG(insulin_final24h) * 100, 2) AS rate_final24h,
  ROUND((AVG(insulin_first24h) - AVG(insulin_final24h)) * 100, 2) AS abs_percentage_difference
FROM patient_flags
UNION ALL
SELECT 
  'oral' AS medication_type,
  ROUND(AVG(oral_first24h) * 100, 2) AS rate_first24h,
  ROUND(AVG(oral_final24h) * 100, 2) AS rate_final24h,
  ROUND((AVG(oral_first24h) - AVG(oral_final24h)) * 100, 2) AS abs_percentage_difference
FROM patient_flags;