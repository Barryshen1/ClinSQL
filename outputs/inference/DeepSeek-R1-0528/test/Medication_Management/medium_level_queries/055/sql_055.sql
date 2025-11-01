WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 39 AND 49
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 72
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        a.hadm_id = diag.hadm_id
        AND (
          (diag.icd_version = 9 AND (diag.icd_code LIKE '250.%0' OR diag.icd_code LIKE '250.%2'))
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'E11%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        a.hadm_id = diag.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
        )
    )
),

insulin_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    -- First 72h flags
    MAX(CASE 
          WHEN p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
          AND (LOWER(p.drug) LIKE '%glargine%' 
               OR LOWER(p.drug) LIKE '%detemir%' 
               OR LOWER(p.drug) LIKE '%nph%' 
               OR LOWER(p.drug) LIKE '%degludec%' 
               OR LOWER(p.drug) LIKE '%basal%') 
          THEN 1 ELSE 0 END) AS basal_first72h,
    MAX(CASE 
          WHEN p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
          AND (LOWER(p.drug) LIKE '%lispro%' 
               OR LOWER(p.drug) LIKE '%aspart%' 
               OR LOWER(p.drug) LIKE '%glulisine%' 
               OR LOWER(p.drug) LIKE '%regular%' 
               OR LOWER(p.drug) LIKE '%bolus%') 
          THEN 1 ELSE 0 END) AS bolus_first72h,
    MAX(CASE 
          WHEN p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
          AND (LOWER(p.drug) LIKE '%sliding scale%' 
               OR LOWER(p.drug) LIKE '%sliding-scale%' 
               OR LOWER(p.drug) LIKE '%ssi%') 
          THEN 1 ELSE 0 END) AS sliding_first72h,
    -- Final 48h flags
    MAX(CASE 
          WHEN p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
          AND (LOWER(p.drug) LIKE '%glargine%' 
               OR LOWER(p.drug) LIKE '%detemir%' 
               OR LOWER(p.drug) LIKE '%nph%' 
               OR LOWER(p.drug) LIKE '%degludec%' 
               OR LOWER(p.drug) LIKE '%basal%') 
          THEN 1 ELSE 0 END) AS basal_final48h,
    MAX(CASE 
          WHEN p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
          AND (LOWER(p.drug) LIKE '%lispro%' 
               OR LOWER(p.drug) LIKE '%aspart%' 
               OR LOWER(p.drug) LIKE '%glulisine%' 
               OR LOWER(p.drug) LIKE '%regular%' 
               OR LOWER(p.drug) LIKE '%bolus%') 
          THEN 1 ELSE 0 END) AS bolus_final48h,
    MAX(CASE 
          WHEN p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
          AND (LOWER(p.drug) LIKE '%sliding scale%' 
               OR LOWER(p.drug) LIKE '%sliding-scale%' 
               OR LOWER(p.drug) LIKE '%ssi%') 
          THEN 1 ELSE 0 END) AS sliding_final48h
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON c.hadm_id = p.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),

cohort_with_bb AS (
  SELECT *,
    -- Basal-bolus = basal AND bolus in same window
    CASE WHEN basal_first72h = 1 AND bolus_first72h = 1 THEN 1 ELSE 0 END AS basal_bolus_first72h,
    CASE WHEN basal_final48h = 1 AND bolus_final48h = 1 THEN 1 ELSE 0 END AS basal_bolus_final48h
  FROM insulin_flags
)

SELECT 
  insulin_type,
  ROUND(first72h_percent, 1) AS first72h_percent,
  ROUND(final48h_percent, 1) AS final48h_percent,
  ROUND(ABS(first72h_percent - final48h_percent), 1) AS abs_percentage_point_diff
FROM (
  SELECT 
    'basal' AS insulin_type,
    AVG(basal_first72h) * 100 AS first72h_percent,
    AVG(basal_final48h) * 100 AS final48h_percent
  FROM cohort_with_bb
  UNION ALL
  SELECT 
    'bolus',
    AVG(bolus_first72h) * 100,
    AVG(bolus_final48h) * 100
  FROM cohort_with_bb
  UNION ALL
  SELECT 
    'basal_bolus',
    AVG(basal_bolus_first72h) * 100,
    AVG(basal_bolus_final48h) * 100
  FROM cohort_with_bb
  UNION ALL
  SELECT 
    'sliding_scale',
    AVG(sliding_first72h) * 100,
    AVG(sliding_final48h) * 100
  FROM cohort_with_bb
) AS result;