WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 63 AND 73
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%' AND LENGTH(d.icd_code) = 5 AND SUBSTR(d.icd_code, 5, 1) IN ('0', '2'))
          OR (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
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

meds AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    CASE WHEN LOWER(p.drug) LIKE '%insulin%' THEN 1 ELSE 0 END AS is_insulin,
    CASE 
      WHEN (
        LOWER(p.drug) LIKE '%metformin%' OR
        LOWER(p.drug) LIKE '%glipizide%' OR
        LOWER(p.drug) LIKE '%glyburide%' OR
        LOWER(p.drug) LIKE '%glimepiride%' OR
        LOWER(p.drug) LIKE '%sitagliptin%' OR
        LOWER(p.drug) LIKE '%saxagliptin%' OR
        LOWER(p.drug) LIKE '%linagliptin%' OR
        LOWER(p.drug) LIKE '%alogliptin%' OR
        LOWER(p.drug) LIKE '%canagliflozin%' OR
        LOWER(p.drug) LIKE '%dapagliflozin%' OR
        LOWER(p.drug) LIKE '%empagliflozin%' OR
        LOWER(p.drug) LIKE '%ertugliflozin%' OR
        LOWER(p.drug) LIKE '%pioglitazone%' OR
        LOWER(p.drug) LIKE '%rosiglitazone%' OR
        LOWER(p.drug) LIKE '%repaglinide%' OR
        LOWER(p.drug) LIKE '%nateglinide%' OR
        LOWER(p.drug) LIKE '%acarbose%' OR
        LOWER(p.drug) LIKE '%miglitol%'
      ) AND LOWER(p.route) IN ('po', 'oral', 'per os') THEN 1 
      ELSE 0 
    END AS is_oral_agent
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE p.hadm_id IN (SELECT hadm_id FROM cohort)
),

admission_meds AS (
  SELECT 
    c.hadm_id,
    MAX(CASE WHEN m.starttime >= c.admittime AND m.starttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR) 
             THEN m.is_insulin ELSE 0 END) AS insulin_first_24h,
    MAX(CASE WHEN m.starttime >= c.admittime AND m.starttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR) 
             THEN m.is_oral_agent ELSE 0 END) AS oral_first_24h,
    MAX(CASE WHEN m.starttime >= DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND m.starttime < c.dischtime 
             THEN m.is_insulin ELSE 0 END) AS insulin_final_24h,
    MAX(CASE WHEN m.starttime >= DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND m.starttime < c.dischtime 
             THEN m.is_oral_agent ELSE 0 END) AS oral_final_24h
  FROM cohort c
  LEFT JOIN meds m ON c.hadm_id = m.hadm_id
  GROUP BY c.hadm_id
)

SELECT
  AVG(insulin_first_24h) * 100 AS insulin_first_24h_pct,
  AVG(insulin_final_24h) * 100 AS insulin_final_24h_pct,
  (AVG(insulin_final_24h) - AVG(insulin_first_24h)) * 100 AS insulin_net_change_pp,
  AVG(oral_first_24h) * 100 AS oral_first_24h_pct,
  AVG(oral_final_24h) * 100 AS oral_final_24h_pct,
  (AVG(oral_final_24h) - AVG(oral_first_24h)) * 100 AS oral_net_change_pp,
  COUNT(*) AS total_admissions
FROM admission_meds;