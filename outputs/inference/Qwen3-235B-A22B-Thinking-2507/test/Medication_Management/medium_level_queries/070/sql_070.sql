WITH cohort_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 68 AND 78
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
        AND d.icd_version = 10 
        AND d.icd_code LIKE 'E11%'
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
        AND d.icd_version = 10 
        AND d.icd_code LIKE 'I50%'
    )
),
drug_flags AS (
  SELECT 
    c.hadm_id,
    -- Metformin
    MAX(CASE 
          WHEN LOWER(p.drug) LIKE '%metformin%' 
            AND p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL '48' HOUR)
            AND COALESCE(p.stoptime, c.dischtime) > c.admittime 
          THEN 1 ELSE 0 
        END) AS metformin_first_48h,
    MAX(CASE 
          WHEN LOWER(p.drug) LIKE '%metformin%' 
            AND p.starttime < c.dischtime 
            AND COALESCE(p.stoptime, c.dischtime) > TIMESTAMP_SUB(c.dischtime, INTERVAL '12' HOUR)
          THEN 1 ELSE 0 
        END) AS metformin_last_12h,
    -- Sulfonylureas
    MAX(CASE 
          WHEN (LOWER(p.drug) LIKE '%glipizide%' OR
                LOWER(p.drug) LIKE '%glyburide%' OR
                LOWER(p.drug) LIKE '%glimepiride%' OR
                LOWER(p.drug) LIKE '%tolbutamide%' OR
                LOWER(p.drug) LIKE '%chlorpropamide%' OR
                LOWER(p.drug) LIKE '%acetohexamide%')
            AND p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL '48' HOUR)
            AND COALESCE(p.stoptime, c.dischtime) > c.admittime 
          THEN 1 ELSE 0 
        END) AS sulfonylureas_first_48h,
    MAX(CASE 
          WHEN (LOWER(p.drug) LIKE '%glipizide%' OR
                LOWER(p.drug) LIKE '%glyburide%' OR
                LOWER(p.drug) LIKE '%glimepiride%' OR
                LOWER(p.drug) LIKE '%tolbutamide%' OR
                LOWER(p.drug) LIKE '%chlorpropamide%' OR
                LOWER(p.drug) LIKE '%acetohexamide%')
            AND p.starttime < c.dischtime 
            AND COALESCE(p.stoptime, c.dischtime) > TIMESTAMP_SUB(c.dischtime, INTERVAL '12' HOUR)
          THEN 1 ELSE 0 
        END) AS sulfonylureas_last_12h,
    -- DPP-4 inhibitors
    MAX(CASE 
          WHEN (LOWER(p.drug) LIKE '%sitagliptin%' OR
                LOWER(p.drug) LIKE '%saxagliptin%' OR
                LOWER(p.drug) LIKE '%linagliptin%' OR
                LOWER(p.drug) LIKE '%alogliptin%')
            AND p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL '48' HOUR)
            AND COALESCE(p.stoptime, c.dischtime) > c.admittime 
          THEN 1 ELSE 0 
        END) AS dpp4_first_48h,
    MAX(CASE 
          WHEN (LOWER(p.drug) LIKE '%sitagliptin%' OR
                LOWER(p.drug) LIKE '%saxagliptin%' OR
                LOWER(p.drug) LIKE '%linagliptin%' OR
                LOWER(p.drug) LIKE '%alogliptin%')
            AND p.starttime < c.dischtime 
            AND COALESCE(p.stoptime, c.dischtime) > TIMESTAMP_SUB(c.dischtime, INTERVAL '12' HOUR)
          THEN 1 ELSE 0 
        END) AS dpp4_last_12h,
    -- SGLT2 inhibitors
    MAX(CASE 
          WHEN (LOWER(p.drug) LIKE '%canagliflozin%' OR
                LOWER(p.drug) LIKE '%dapagliflozin%' OR
                LOWER(p.drug) LIKE '%empagliflozin%' OR
                LOWER(p.drug) LIKE '%ertugliflozin%')
            AND p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL '48' HOUR)
            AND COALESCE(p.stoptime, c.dischtime) > c.admittime 
          THEN 1 ELSE 0 
        END) AS sglt2_first_48h,
    MAX(CASE 
          WHEN (LOWER(p.drug) LIKE '%canagliflozin%' OR
                LOWER(p.drug) LIKE '%dapagliflozin%' OR
                LOWER(p.drug) LIKE '%empagliflozin%' OR
                LOWER(p.drug) LIKE '%ertugliflozin%')
            AND p.starttime < c.dischtime 
            AND COALESCE(p.stoptime, c.dischtime) > TIMESTAMP_SUB(c.dischtime, INTERVAL '12' HOUR)
          THEN 1 ELSE 0 
        END) AS sglt2_last_12h
  FROM cohort_admissions c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  GROUP BY c.hadm_id
)
SELECT 
  'metformin' AS drug_class,
  SUM(metformin_first_48h) * 100.0 / COUNT(*) AS prevalence_first_48h,
  SUM(metformin_last_12h) * 100.0 / COUNT(*) AS prevalence_last_12h,
  (SUM(metformin_last_12h) - SUM(metformin_first_48h)) * 100.0 / COUNT(*) AS net_change
FROM drug_flags

UNION ALL

SELECT 
  'sulfonylureas',
  SUM(sulfonylureas_first_48h) * 100.0 / COUNT(*),
  SUM(sulfonylureas_last_12h) * 100.0 / COUNT(*),
  (SUM(sulfonylureas_last_12h) - SUM(sulfonylureas_first_48h)) * 100.0 / COUNT(*)
FROM drug_flags

UNION ALL

SELECT 
  'DPP-4 inhibitors',
  SUM(dpp4_first_48h) * 100.0 / COUNT(*),
  SUM(dpp4_last_12h) * 100.0 / COUNT(*),
  (SUM(dpp4_last_12h) - SUM(dpp4_first_48h)) * 100.0 / COUNT(*)
FROM drug_flags

UNION ALL

SELECT 
  'SGLT2 inhibitors',
  SUM(sglt2_first_48h) * 100.0 / COUNT(*),
  SUM(sglt2_last_12h) * 100.0 / COUNT(*),
  (SUM(sglt2_last_12h) - SUM(sglt2_first_48h)) * 100.0 / COUNT(*)
FROM drug_flags;