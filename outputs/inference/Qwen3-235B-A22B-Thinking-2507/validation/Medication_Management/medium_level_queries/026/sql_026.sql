WITH target_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 38 AND 48
    AND a.hadm_id IN (
      SELECT d.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE 
        (d.icd_version = 9 AND dd.long_title LIKE '%type ii%') 
        OR (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
      GROUP BY d.hadm_id
    )
    AND a.hadm_id IN (
      SELECT d.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE 
        (d.icd_version = 9 AND d.icd_code LIKE '428%') 
        OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
      GROUP BY d.hadm_id
    )
),
drug_initiation AS (
  SELECT 
    p.hadm_id,
    MIN(CASE 
          WHEN LOWER(p.drug) LIKE '%insulin%' 
            AND LOWER(p.drug) NOT LIKE '%pump%' 
          THEN p.starttime 
        END) AS first_insulin_time,
    MIN(CASE 
          WHEN LOWER(p.drug) LIKE '%metformin%' 
            OR LOWER(p.drug) LIKE '%glipizide%' 
            OR LOWER(p.drug) LIKE '%glyburide%' 
            OR LOWER(p.drug) LIKE '%glimepiride%' 
            OR LOWER(p.drug) LIKE '%sitagliptin%' 
            OR LOWER(p.drug) LIKE '%saxagliptin%' 
            OR LOWER(p.drug) LIKE '%linagliptin%' 
            OR LOWER(p.drug) LIKE '%alogliptin%' 
            OR LOWER(p.drug) LIKE '%pioglitazone%' 
            OR LOWER(p.drug) LIKE '%rosiglitazone%' 
            OR LOWER(p.drug) LIKE '%repaglinide%' 
            OR LOWER(p.drug) LIKE '%nateglinide%' 
            OR LOWER(p.drug) LIKE '%acarbose%' 
            OR LOWER(p.drug) LIKE '%miglitol%' 
            OR LOWER(p.drug) LIKE '%dapagliflozin%' 
            OR LOWER(p.drug) LIKE '%canagliflozin%' 
            OR LOWER(p.drug) LIKE '%empagliflozin%' 
            OR LOWER(p.drug) LIKE '%ertugliflozin%' 
          THEN p.starttime 
        END) AS first_oral_time
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN target_admissions ta
    ON p.hadm_id = ta.hadm_id
  GROUP BY p.hadm_id
),
time_windows AS (
  SELECT 
    ta.hadm_id,
    ta.admittime,
    ta.dischtime,
    di.first_insulin_time,
    di.first_oral_time,
    LEAST(TIMESTAMP_ADD(ta.admittime, INTERVAL 72 HOUR), ta.dischtime) AS first_72h_end,
    GREATEST(TIMESTAMP_SUB(ta.dischtime, INTERVAL 72 HOUR), ta.admittime) AS final_72h_start
  FROM target_admissions ta
  LEFT JOIN drug_initiation di
    ON ta.hadm_id = di.hadm_id
),
initiation_flags AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN first_insulin_time IS NOT NULL 
        AND first_insulin_time <= first_72h_end 
      THEN 1 ELSE 0 
    END AS first_72h_insulin,
    CASE 
      WHEN first_oral_time IS NOT NULL 
        AND first_oral_time <= first_72h_end 
      THEN 1 ELSE 0 
    END AS first_72h_oral,
    CASE 
      WHEN first_insulin_time IS NOT NULL 
        AND first_insulin_time >= final_72h_start 
      THEN 1 ELSE 0 
    END AS final_72h_insulin,
    CASE 
      WHEN first_oral_time IS NOT NULL 
        AND first_oral_time >= final_72h_start 
      THEN 1 ELSE 0 
    END AS final_72h_oral
  FROM time_windows
)
SELECT 
  (SUM(first_72h_insulin) * 100.0) / COUNT(*) AS first_72h_insulin_pct,
  (SUM(first_72h_oral) * 100.0) / COUNT(*) AS first_72h_oral_pct,
  (SUM(final_72h_insulin) * 100.0) / COUNT(*) AS final_72h_insulin_pct,
  (SUM(final_72h_oral) * 100.0) / COUNT(*) AS final_72h_oral_pct
FROM initiation_flags;