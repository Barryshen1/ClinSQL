WITH base_cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'M'
    -- Filter age 89-99 at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 89 AND 99
    -- Hemorrhagic stroke diagnosis (any position)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE adm.hadm_id = diag.hadm_id
        AND (
          (diag.icd_version = 9 AND (diag.icd_code IN ('430', '431') OR diag.icd_code LIKE '432%'))
          OR 
          (diag.icd_version = 10 AND (diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%' OR diag.icd_code LIKE 'I62%'))
        )
    )
),

-- Count distinct drugs in first 7 days
med_counts AS (
  SELECT 
    bc.hadm_id,
    COUNT(DISTINCT pr.drug) AS drug_count
  FROM base_cohort bc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON bc.hadm_id = pr.hadm_id
    AND pr.starttime >= bc.admittime
    AND pr.starttime <= TIMESTAMP_ADD(bc.admittime, INTERVAL 7 DAY)
  GROUP BY bc.hadm_id
),

-- Combine cohort with drug counts
cohort_with_meds AS (
  SELECT 
    bc.*,
    COALESCE(mc.drug_count, 0) AS drug_count
  FROM base_cohort bc
  LEFT JOIN med_counts mc
    ON bc.hadm_id = mc.hadm_id
),

-- Assign medication complexity quintiles
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY drug_count) AS med_quintile
  FROM cohort_with_meds
),

-- Calculate readmission flag (for survivors only)
cohort_with_readmission AS (
  SELECT 
    q.*,
    -- Set readmission_flag to NULL for in-hospital deaths
    CASE 
      WHEN q.hospital_expire_flag = 1 THEN NULL 
      -- Check for readmission within 30 days of discharge
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` readm
        WHERE q.subject_id = readm.subject_id
          AND readm.hadm_id != q.hadm_id  -- Exclude index admission
          AND readm.admittime > q.dischtime
          AND readm.admittime <= TIMESTAMP_ADD(q.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0 
    END AS readmission_flag
  FROM quintiles q
)

-- Final aggregation by quintile
SELECT 
  med_quintile,
  COUNT(*) AS num_admissions,
  AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los,
  AVG(hospital_expire_flag) * 100 AS mortality_rate_percent,
  AVG(readmission_flag) * 100 AS readmission_rate_percent  -- Among survivors
FROM cohort_with_readmission
GROUP BY med_quintile
ORDER BY med_quintile;