WITH patient_cohort AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (a.admittime BETWEEN DATETIME(p.anchor_year - (50 - p.anchor_age), 1, 1, 0, 0, 0) 
                  AND DATETIME(p.anchor_year - (40 - p.anchor_age), 12, 31, 23, 59, 59))
    AND TIMESTAMPDIFF(a.dischtime, a.admittime, HOUR) >= 72
),
t2dm_hf_cohort AS (
  SELECT pc.subject_id
  FROM patient_cohort pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pc.subject_id = di.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (d.icd_code LIKE 'E11%' AND d.icd_version = 10)  -- T2DM
  GROUP BY pc.subject_id
  HAVING COUNT(CASE WHEN d.icd_code LIKE 'I50%' THEN 1 END) >= 1  -- Heart Failure
),
insulin_orders AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    pr.drug,
    pr.starttime,
    CASE
      WHEN LOWER(pr.drug) LIKE '%basal%' OR LOWER(pr.drug) LIKE '%long%' OR LOWER(pr.drug) LIKE '%glargine%'
        OR LOWER(pr.drug) LIKE '%detemir%' OR LOWER(pr.drug) LIKE '%degludec%' THEN 'basal'
      WHEN LOWER(pr.drug) LIKE '%bolus%' OR LOWER(pr.drug) LIKE '%rapid%' OR LOWER(pr.drug) LIKE '%lispro%'
        OR LOWER(pr.drug) LIKE '%aspart%' OR LOWER(pr.drug) LIKE '%glulisine%' THEN 'bolus'
      WHEN (LOWER(pr.drug) LIKE '%basal%' OR LOWER(pr.drug) LIKE '%long%') 
        AND (LOWER(pr.drug) LIKE '%bolus%' OR LOWER(pr.drug) LIKE '%rapid%') THEN 'basal-bolus'
      WHEN LOWER(pr.drug) LIKE '%sliding scale%' OR LOWER(pr.drug) LIKE '%correction%' THEN 'sliding-scale'
      ELSE NULL
    END AS insulin_type
  FROM t2dm_hf_cohort t
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON t.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
    ON a.hadm_id = pr.hadm_id
  WHERE LOWER(pr.drug) LIKE '%insulin%'
    AND pr.starttime IS NOT NULL
),
time_windows AS (
  SELECT 
    subject_id,
    hadm_id,
    starttime,
    insulin_type,
    CASE WHEN starttime <= DATETIME_ADD(admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END AS in_first_72h,
    CASE WHEN starttime >= DATETIME_ADD(dischtime, INTERVAL -48 HOUR) THEN 1 ELSE 0 END AS in_final_48h
  FROM insulin_orders
),
regimen_initiation AS (
  SELECT 
    insulin_type,
    MAX(in_first_72h) AS initiated_first_72h,
    MAX(in_final_48h) AS initiated_final_48h
  FROM time_windows
  WHERE insulin_type IS NOT NULL
  GROUP BY subject_id, hadm_id, insulin_type
),
summary_stats AS (
  SELECT
    insulin_type,
    AVG(CAST(initiated_first_72h AS FLOAT64)) * 100 AS pct_first_72h,
    AVG(CAST(initiated_final_48h AS FLOAT64)) * 100 AS pct_final_48h
  FROM regimen_initiation
  GROUP BY insulin_type
)
SELECT
  insulin_type,
  ROUND(pct_first_72h, 2) AS pct_first_72h,
  ROUND(pct_final_48h, 2) AS pct_final_48h,
  ROUND(pct_final_48h - pct_first_72h, 2) AS absolute_difference
FROM summary_stats
ORDER BY insulin_type;