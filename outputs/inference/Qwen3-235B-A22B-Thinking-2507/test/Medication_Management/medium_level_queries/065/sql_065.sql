WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 77 AND 87
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250.%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' 
              OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%')
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),
insulin_events AS (
  SELECT 
    p.hadm_id,
    p.starttime AS drug_time
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE 
    LOWER(p.drug) LIKE '%insulin%'
    AND LOWER(p.drug) NOT LIKE '%insulin-like%'
    AND LOWER(p.drug) NOT LIKE '%insulin receptor%'
    AND LOWER(p.drug) NOT LIKE '%insulin growth%'
    AND LOWER(p.drug) NOT LIKE '%insulinoma%'
  
  UNION ALL
  
  SELECT 
    i.hadm_id,
    i.starttime AS drug_time
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d 
    ON i.itemid = d.itemid
  WHERE 
    LOWER(d.label) LIKE '%insulin%'
    AND LOWER(d.label) NOT LIKE '%insulin-like%'
    AND LOWER(d.label) NOT LIKE '%insulin receptor%'
    AND LOWER(d.label) NOT LIKE '%insulin growth%'
    AND LOWER(d.label) NOT LIKE '%insulinoma%'
),
oral_events AS (
  SELECT 
    p.hadm_id,
    p.starttime AS drug_time
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE 
    LOWER(p.drug) IN (
      'metformin', 'glipizide', 'glyburide', 'glimepiride', 'sitagliptin', 'saxagliptin', 
      'linagliptin', 'alogliptin', 'canagliflozin', 'dapagliflozin', 'empagliflozin', 
      'ertugliflozin', 'pioglitazone', 'rosiglitazone', 'repaglinide', 'nateglinide'
    )
    OR LOWER(p.drug) LIKE '%metformin%'
    OR LOWER(p.drug) LIKE '%glipizide%'
    OR LOWER(p.drug) LIKE '%glyburide%'
    OR LOWER(p.drug) LIKE '%glimepiride%'
    OR LOWER(p.drug) LIKE '%sitagliptin%'
    OR LOWER(p.drug) LIKE '%saxagliptin%'
    OR LOWER(p.drug) LIKE '%linagliptin%'
    OR LOWER(p.drug) LIKE '%alogliptin%'
    OR LOWER(p.drug) LIKE '%canagliflozin%'
    OR LOWER(p.drug) LIKE '%dapagliflozin%'
    OR LOWER(p.drug) LIKE '%empagliflozin%'
    OR LOWER(p.drug) LIKE '%ertugliflozin%'
    OR LOWER(p.drug) LIKE '%pioglitazone%'
    OR LOWER(p.drug) LIKE '%rosiglitazone%'
    OR LOWER(p.drug) LIKE '%repaglinide%'
    OR LOWER(p.drug) LIKE '%nateglinide%'
),
first_admins AS (
  SELECT
    c.hadm_id,
    MIN(i.drug_time) AS first_insulin_time,
    MIN(o.drug_time) AS first_oral_time
  FROM cohort c
  LEFT JOIN insulin_events i ON c.hadm_id = i.hadm_id
  LEFT JOIN oral_events o ON c.hadm_id = o.hadm_id
  GROUP BY c.hadm_id
),
initiation_flags AS (
  SELECT
    c.hadm_id,
    CASE WHEN fa.first_insulin_time BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END AS insulin_early,
    CASE WHEN fa.first_oral_time BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END AS oral_early,
    CASE WHEN fa.first_insulin_time BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime THEN 1 ELSE 0 END AS insulin_late,
    CASE WHEN fa.first_oral_time BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime THEN 1 ELSE 0 END AS oral_late
  FROM cohort c
  LEFT JOIN first_admins fa ON c.hadm_id = fa.hadm_id
)
SELECT
  'insulin' AS drug_class,
  AVG(insulin_early) AS early_rate,
  AVG(insulin_late) AS late_rate,
  AVG(insulin_late) - AVG(insulin_early) AS net_change
FROM initiation_flags

UNION ALL

SELECT
  'oral' AS drug_class,
  AVG(oral_early) AS early_rate,
  AVG(oral_late) AS late_rate,
  AVG(oral_late) - AVG(oral_early) AS net_change
FROM initiation_flags;