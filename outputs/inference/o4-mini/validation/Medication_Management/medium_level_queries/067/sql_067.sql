WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'E1%'  -- diabetes
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'I50.2%'  -- acute HF
    )
),
meds AS (
  SELECT
    p.hadm_id,
    p.starttime,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(p.drug) LIKE '%glipizide%' 
        OR LOWER(p.drug) LIKE '%glyburide%' 
        OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' 
        OR LOWER(p.drug) LIKE '%saxagliptin%' 
        OR LOWER(p.drug) LIKE '%linagliptin%' 
        OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'DPP-4'
      WHEN LOWER(p.drug) LIKE '%flozin%' THEN 'SGLT2'
      WHEN LOWER(p.drug) LIKE '%tide%' THEN 'GLP-1'
      WHEN LOWER(p.drug) LIKE '%glitazone%' 
        OR LOWER(p.drug) LIKE '%pioglitazone%' 
        OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'TZDs'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE LOWER(p.drug) LIKE '%insulin%'
     OR LOWER(p.drug) LIKE '%metformin%'
     OR LOWER(p.drug) LIKE '%glipizide%'
     OR LOWER(p.drug) LIKE '%glyburide%'
     OR LOWER(p.drug) LIKE '%glimepiride%'
     OR LOWER(p.drug) LIKE '%sitagliptin%'
     OR LOWER(p.drug) LIKE '%saxagliptin%'
     OR LOWER(p.drug) LIKE '%linagliptin%'
     OR LOWER(p.drug) LIKE '%alogliptin%'
     OR LOWER(p.drug) LIKE '%flozin%'
     OR LOWER(p.drug) LIKE '%tide%'
     OR LOWER(p.drug) LIKE '%glitazone%'
     -- filter out rows without a class
     AND (
       LOWER(p.drug) LIKE '%insulin%'
       OR LOWER(p.drug) LIKE '%metformin%'
       OR LOWER(p.drug) LIKE '%glipizide%'
       OR LOWER(p.drug) LIKE '%glyburide%'
       OR LOWER(p.drug) LIKE '%glimepiride%'
       OR LOWER(p.drug) LIKE '%sitagliptin%'
       OR LOWER(p.drug) LIKE '%saxagliptin%'
       OR LOWER(p.drug) LIKE '%linagliptin%'
       OR LOWER(p.drug) LIKE '%alogliptin%'
       OR LOWER(p.drug) LIKE '%flozin%'
       OR LOWER(p.drug) LIKE '%tide%'
       OR LOWER(p.drug) LIKE '%glitazone%'
     )
),
med_inits AS (
  SELECT
    c.hadm_id,
    m.drug_class,
    MIN(m.starttime) AS first_starttime
  FROM cohort c
  JOIN meds m
    ON c.hadm_id = m.hadm_id
   AND m.starttime BETWEEN c.admittime AND c.dischtime
  WHERE m.drug_class IS NOT NULL
  GROUP BY c.hadm_id, m.drug_class
),
flags AS (
  SELECT
    m.drug_class,
    COUNT(DISTINCT m.hadm_id) AS n_adm_with_class,
    SUM(CASE 
          WHEN m.first_starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
          THEN 1 ELSE 0 END
       ) AS n_first12h,
    SUM(CASE 
          WHEN m.first_starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR)
          THEN 1 ELSE 0 END
       ) AS n_last48h
  FROM med_inits m
  JOIN cohort c
    ON m.hadm_id = c.hadm_id
  GROUP BY m.drug_class
),
denominator AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_admissions
  FROM cohort
)
SELECT
  f.drug_class,
  ROUND(100.0 * f.n_first12h  / d.total_admissions, 1) AS pct_initiated_first_12h,
  ROUND(100.0 * f.n_last48h   / d.total_admissions, 1) AS pct_initiated_last_48h
FROM flags f
CROSS JOIN denominator d
ORDER BY f.drug_class;