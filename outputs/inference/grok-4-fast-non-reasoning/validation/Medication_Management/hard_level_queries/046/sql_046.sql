WITH cohort AS (
  -- Base cohort: females 45-55
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
),

trauma_cohort AS (
  -- Filter for multi-trauma: >=2 distinct trauma ICD-10 codes (T07 or injury S/T)
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.anchor_age,
    COUNT(DISTINCT CASE 
      WHEN icd.icd_code LIKE 'T07%' 
        OR (icd.icd_code LIKE 'S%' AND LENGTH(icd.icd_code) >= 3)
        OR (icd.icd_code LIKE 'T3%' OR icd.icd_code LIKE 'T4%' OR icd.icd_code LIKE 'T5%' OR icd.icd_code LIKE 'T6%')
      THEN icd.icd_code 
    END) AS trauma_count
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` icd
  ON c.hadm_id = icd.hadm_id
  WHERE 
    icd.icd_version = 10
  GROUP BY 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag, c.anchor_age
  HAVING 
    trauma_count >= 2  -- Multi-trauma definition
),

med_complexity AS (
  -- Compute distinct meds in first 7 days using pharmacy (more complete than prescriptions)
  SELECT 
    tc.*,
    COUNT(DISTINCT LOWER(TRIM(pharm.medication))) AS complexity_score
  FROM 
    trauma_cohort tc
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.pharmacy` pharm
  ON tc.subject_id = pharm.subject_id
    AND tc.hadm_id = pharm.hadm_id
    AND pharm.medication IS NOT NULL
    AND pharm.starttime >= tc.admittime
    AND pharm.starttime < TIMESTAMP_ADD(tc.admittime, INTERVAL 7 DAY)
  GROUP BY 
    tc.subject_id, tc.hadm_id, tc.admittime, tc.dischtime, tc.hospital_expire_flag, tc.anchor_age
),

tertiles AS (
  -- Assign tertiles
  SELECT 
    *,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM 
    med_complexity
),

readmission_flags AS (
  -- Flag 30-day readmissions
  SELECT 
    t.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` next_a
        WHERE next_a.subject_id = t.subject_id
          AND next_a.hadm_id != t.hadm_id
          AND next_a.admittime > t.dischtime
          AND next_a.admittime <= TIMESTAMP_ADD(t.dischtime, INTERVAL 30 DAY)
      ) THEN 1 
      ELSE 0 
    END AS has_readmission
  FROM 
    tertiles t
)

-- Aggregate metrics by tertile
SELECT 
  tertile,
  COUNT(*) AS num_admissions,
  ROUND(AVG(complexity_score), 2) AS mean_score,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  ROUND(AVG(EXTRACT(DAY FROM (dischtime - admittime))), 2) AS mean_los_days,
  ROUND((SUM(CAST(hospital_expire_flag AS INT64)) * 100.0 / COUNT(*)), 2) AS mortality_pct,
  ROUND((SUM(has_readmission) * 100.0 / COUNT(*)), 2) AS readmission_30d_pct
FROM 
  readmission_flags
GROUP BY 
  tertile
ORDER BY 
  tertile;