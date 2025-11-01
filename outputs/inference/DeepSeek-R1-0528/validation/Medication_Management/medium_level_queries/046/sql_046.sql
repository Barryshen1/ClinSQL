WITH eligible_admissions AS (
  SELECT 
      a.subject_id, 
      a.hadm_id, 
      a.admittime, 
      a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE 
      p.gender = 'M'
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 63 AND 73
      AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 24
      AND a.hadm_id IN (
          SELECT hadm_id 
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
          WHERE 
              (icd_version = 9 AND icd_code LIKE '250%' AND SUBSTR(icd_code, LENGTH(icd_code), 1) IN ('0','2'))
              OR (icd_version = 10 AND icd_code LIKE 'E11%')
      )
      AND a.hadm_id IN (
          SELECT hadm_id 
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
          WHERE 
              (icd_version = 9 AND icd_code LIKE '428%')
              OR (icd_version = 10 AND icd_code LIKE 'I50%')
      )
), 

medication_flags AS (
  SELECT 
      e.hadm_id,
      -- Insulin flags
      MAX(CASE 
          WHEN LOWER(p.drug) LIKE '%insulin%' 
          AND p.starttime BETWEEN e.admittime AND DATETIME_ADD(e.admittime, INTERVAL 24 HOUR) 
          THEN 1 ELSE 0 
      END) AS insulin_first24h,
      MAX(CASE 
          WHEN LOWER(p.drug) LIKE '%insulin%' 
          AND p.starttime BETWEEN DATETIME_SUB(e.dischtime, INTERVAL 24 HOUR) AND e.dischtime 
          THEN 1 ELSE 0 
      END) AS insulin_final24h,
      -- Oral agents flags
      MAX(CASE 
          WHEN (
            LOWER(p.drug) LIKE '%metformin%' OR
            LOWER(p.drug) LIKE '%glipizide%' OR
            LOWER(p.drug) LIKE '%glyburide%' OR
            LOWER(p.drug) LIKE '%glimepiride%' OR
            LOWER(p.drug) LIKE '%pioglitazone%' OR
            LOWER(p.drug) LIKE '%rosiglitazone%' OR
            LOWER(p.drug) LIKE '%sitagliptin%' OR
            LOWER(p.drug) LIKE '%saxagliptin%' OR
            LOWER(p.drug) LIKE '%linagliptin%' OR
            LOWER(p.drug) LIKE '%alogliptin%' OR
            LOWER(p.drug) LIKE '%canagliflozin%' OR
            LOWER(p.drug) LIKE '%dapagliflozin%' OR
            LOWER(p.drug) LIKE '%empagliflozin%' OR
            LOWER(p.drug) LIKE '%repaglinide%' OR
            LOWER(p.drug) LIKE '%nateglinide%' OR
            LOWER(p.drug) LIKE '%acarbose%' OR
            LOWER(p.drug) LIKE '%miglitol%'
          )
          AND p.starttime BETWEEN e.admittime AND DATETIME_ADD(e.admittime, INTERVAL 24 HOUR) 
          THEN 1 ELSE 0 
      END) AS oral_first24h,
      MAX(CASE 
          WHEN (
            LOWER(p.drug) LIKE '%metformin%' OR
            LOWER(p.drug) LIKE '%glipizide%' OR
            LOWER(p.drug) LIKE '%glyburide%' OR
            LOWER(p.drug) LIKE '%glimepiride%' OR
            LOWER(p.drug) LIKE '%pioglitazone%' OR
            LOWER(p.drug) LIKE '%rosiglitazone%' OR
            LOWER(p.drug) LIKE '%sitagliptin%' OR
            LOWER(p.drug) LIKE '%saxagliptin%' OR
            LOWER(p.drug) LIKE '%linagliptin%' OR
            LOWER(p.drug) LIKE '%alogliptin%' OR
            LOWER(p.drug) LIKE '%canagliflozin%' OR
            LOWER(p.drug) LIKE '%dapagliflozin%' OR
            LOWER(p.drug) LIKE '%empagliflozin%' OR
            LOWER(p.drug) LIKE '%repaglinide%' OR
            LOWER(p.drug) LIKE '%nateglinide%' OR
            LOWER(p.drug) LIKE '%acarbose%' OR
            LOWER(p.drug) LIKE '%miglitol%'
          )
          AND p.starttime BETWEEN DATETIME_SUB(e.dischtime, INTERVAL 24 HOUR) AND e.dischtime 
          THEN 1 ELSE 0 
      END) AS oral_final24h
  FROM eligible_admissions e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON e.hadm_id = p.hadm_id
  GROUP BY e.hadm_id
)

SELECT 
    'Insulin' AS medication,
    ROUND(AVG(insulin_first24h) * 100, 2) AS prevalence_first24h,
    ROUND(AVG(insulin_final24h) * 100, 2) AS prevalence_final24h,
    ROUND((AVG(insulin_final24h) - AVG(insulin_first24h)) * 100, 2) AS net_change_pp
FROM medication_flags
UNION ALL
SELECT 
    'Oral Agents' AS medication,
    ROUND(AVG(oral_first24h) * 100, 2) AS prevalence_first24h,
    ROUND(AVG(oral_final24h) * 100, 2) AS prevalence_final24h,
    ROUND((AVG(oral_final24h) - AVG(oral_first24h)) * 100, 2) AS net_change_pp
FROM medication_flags;