WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 63 AND 73
    AND adm.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
    AND adm.hadm_id IN (
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code LIKE 'E11%' AND icd_version = 10
    )
    AND adm.hadm_id IN (
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code LIKE 'I50%' AND icd_version = 10
    )
    AND adm.dischtime > DATETIME_ADD(adm.admittime, INTERVAL 24 HOUR)
),
insulin_first24h AS (
  SELECT 
    c.hadm_id,
    MAX(1) AS insulin_first24h
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  WHERE e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
    AND LOWER(e.medication) LIKE '%insulin%'
  GROUP BY c.hadm_id
),
insulin_last24h AS (
  SELECT 
    c.hadm_id,
    MAX(1) AS insulin_last24h
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  WHERE e.charttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
    AND LOWER(e.medication) LIKE '%insulin%'
  GROUP BY c.hadm_id
),
oral_first24h AS (
  SELECT 
    c.hadm_id,
    MAX(1) AS oral_first24h
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  WHERE e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
    AND (LOWER(e.medication) LIKE '%metformin%' 
         OR LOWER(e.medication) LIKE '%glipizide%'
         OR LOWER(e.medication) LIKE '%glyburide%'
         OR LOWER(e.medication) LIKE '%pioglitazone%'
         OR LOWER(e.medication) LIKE '%sitagliptin%'
         OR LOWER(e.medication) LIKE '%januvia%'
         OR LOWER(e.medication) LIKE '%glimepiride%'
         OR LOWER(e.medication) LIKE '%nateglinide%'
         OR LOWER(e.medication) LIKE '%repaglinide%'
         OR LOWER(e.medication) LIKE '%acarbose%'
         OR LOWER(e.medication) LIKE '%miglitol%'
         OR LOWER(e.medication) LIKE '%rosiglitazone%'
         OR LOWER(e.medication) LIKE '%linagliptin%'
         OR LOWER(e.medication) LIKE '%saxagliptin%'
         OR LOWER(e.medication) LIKE '%dapagliflozin%'
         OR LOWER(e.medication) LIKE '%canagliflozin%'
         OR LOWER(e.medication) LIKE '%empagliflozin%')
  GROUP BY c.hadm_id
),
oral_last24h AS (
  SELECT 
    c.hadm_id,
    MAX(1) AS oral_last24h
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  WHERE e.charttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
    AND (LOWER(e.medication) LIKE '%metformin%' 
         OR LOWER(e.medication) LIKE '%glipizide%'
         OR LOWER(e.medication) LIKE '%glyburide%'
         OR LOWER(e.medication) LIKE '%pioglitazone%'
         OR LOWER(e.medication) LIKE '%sitagliptin%'
         OR LOWER(e.medication) LIKE '%januvia%'
         OR LOWER(e.medication) LIKE '%glimepiride%'
         OR LOWER(e.medication) LIKE '%nateglinide%'
         OR LOWER(e.medication) LIKE '%repaglinide%'
         OR LOWER(e.medication) LIKE '%acarbose%'
         OR LOWER(e.medication) LIKE '%miglitol%'
         OR LOWER(e.medication) LIKE '%rosiglitazone%'
         OR LOWER(e.medication) LIKE '%linagliptin%'
         OR LOWER(e.medication) LIKE '%saxagliptin%'
         OR LOWER(e.medication) LIKE '%dapagliflozin%'
         OR LOWER(e.medication) LIKE '%canagliflozin%'
         OR LOWER(e.medication) LIKE '%empagliflozin%')
  GROUP BY c.hadm_id
),
cohort_meds AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    COALESCE(i1.insulin_first24h, 0) AS insulin_first24h,
    COALESCE(i2.insulin_last24h, 0) AS insulin_last24h,
    COALESCE(o1.oral_first24h, 0) AS oral_first24h,
    COALESCE(o2.oral_last24h, 0) AS oral_last24h
  FROM cohort c
  LEFT JOIN insulin_first24h i1 ON c.hadm_id = i1.hadm_id
  LEFT JOIN insulin_last24h i2 ON c.hadm_id = i2.hadm_id
  LEFT JOIN oral_first24h o1 ON c.hadm_id = o1.hadm_id
  LEFT JOIN oral_last24h o2 ON c.hadm_id = o2.hadm_id
)
SELECT 
  COUNT(*) AS total_patients,
  ROUND(100 * SUM(insulin_first24h) / COUNT(*), 2) AS insulin_first24h_percent,
  ROUND(100 * SUM(insulin_last24h) / COUNT(*), 2) AS insulin_last24h_percent,
  ROUND(100 * SUM(oral_first24h) / COUNT(*), 2) AS oral_first24h_percent,
  ROUND(100 * SUM(oral_last24h) / COUNT(*), 2) AS oral_last24h_percent,
  ROUND(100 * SUM(insulin_last24h) / COUNT(*) - 100 * SUM(insulin_first24h) / COUNT(*), 2) AS insulin_net_change_pp,
  ROUND(100 * SUM(oral_last24h) / COUNT(*) - 100 * SUM(oral_first24h) / COUNT(*), 2) AS oral_net_change_pp
FROM cohort_meds;