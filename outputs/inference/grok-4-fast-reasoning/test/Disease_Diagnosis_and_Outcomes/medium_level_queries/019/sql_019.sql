WITH cohort_hadm AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 53 AND 63
    AND (
      (di.icd_version = '9' AND di.icd_code LIKE '428%') 
      OR (di.icd_version = '10' AND di.icd_code LIKE 'I50%')
    )
),
charlson_flags AS (
  SELECT 
    c.hadm_id,
    -- MI (weight 1)
    MAX(CASE 
      WHEN (
        (d.icd_version = '9' AND (d.icd_code LIKE '410.%' OR d.icd_code LIKE '412.%')) 
        OR (d.icd_version = '10' AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I25.2'))
      ) THEN 1 
      ELSE 0 
    END) AS mi_score,
    -- CHF (weight 1)
    MAX(CASE 
      WHEN (
        (d.icd_version = '9' AND d.icd_code LIKE '428%') 
        OR (d.icd_version = '10' AND d.icd_code LIKE 'I50%')
      ) THEN 1 
      ELSE 0 
    END) AS chf_score,
    -- PVD (weight 1, simplified)
    MAX(CASE 
      WHEN (
        (d.icd_version = '9' AND (d.icd_code LIKE '443.1%' OR d.icd_code = '441.9')) 
        OR (d.icd_version = '10' AND d.icd_code LIKE 'I70%')
      ) THEN 1 
      ELSE 0 
    END) AS pvd_score,
    -- COPD (weight 1)
    MAX(CASE 
      WHEN (
        (d.icd_version = '9' AND (d.icd_code LIKE '490%' OR d.icd_code LIKE '491%' OR d.icd_code LIKE '492%' OR d.icd_code LIKE '493%' OR d.icd_code LIKE '494%' OR d.icd_code LIKE '495%' OR d.icd_code LIKE '496%')) 
        OR (d.icd_version = '10' AND (d.icd_code LIKE 'J40%' OR d.icd_code LIKE 'J41%' OR d.icd_code LIKE 'J42%' OR d.icd_code LIKE 'J43%' OR d.icd_code LIKE 'J44%' OR d.icd_code LIKE 'J47%'))
      ) THEN 1 
      ELSE 0 
    END) AS copd_score,
    -- Diabetes uncomplicated (weight 1, simplified)
    MAX(CASE 
      WHEN (
        (d.icd_version = '9' AND (d.icd_code LIKE '250.0%' OR d.icd_code LIKE '250.1%' OR d.icd_code LIKE '250.2%' OR d.icd_code LIKE '250.3%')) 
        OR (d.icd_version = '10' AND (d.icd_code LIKE 'E10.0%' OR d.icd_code LIKE 'E10.1%' OR d.icd_code LIKE 'E10.9%' OR d.icd_code LIKE 'E11.0%' OR d.icd_code LIKE 'E11.1%' OR d.icd_code LIKE 'E11.9%'))
      ) THEN 1 
      ELSE 0 
    END) AS diabetes_score,
    -- Renal disease (weight 2, simplified)
    MAX(CASE 
      WHEN (
        (d.icd_version = '9' AND (d.icd_code LIKE '582%' OR d.icd_code LIKE '583%' OR d.icd_code LIKE '585%' OR d.icd_code LIKE '586%')) 
        OR (d.icd_version = '10' AND (d.icd_code LIKE 'N18%' OR d.icd_code LIKE 'N19%'))
      ) THEN 2 
      ELSE 0 
    END) AS renal_score
    -- Note: Add remaining components (e.g., dementia, malignancy, metastatic, AIDS, liver, etc.) similarly using Quan mappings for full score
  FROM cohort_hadm c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON c.hadm_id = d.hadm_id
  GROUP BY c.hadm_id
),
charlson AS (
  SELECT 
    hadm_id,
    (mi_score + chf_score + pvd_score + copd_score + diabetes_score + renal_score) AS charlson_score  -- Partial; add other scores for full
  FROM charlson_flags
),
admissions_with_los AS (
  SELECT 
    c.hadm_id,
    a.dischtime,
    a.admittime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM cohort_hadm c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
  WHERE a.dischtime IS NOT NULL
)
SELECT 
  CASE 
    WHEN los_days <= 3 THEN '1-3'
    WHEN los_days <= 7 THEN '4-7'
    ELSE '>=8'
  END AS los_cat,
  CASE 
    WHEN ch.charlson_score <= 3 THEN '<=3'
    WHEN ch.charlson_score BETWEEN 4 AND 5 THEN '4-5'
    ELSE '>5'
  END AS charlson_cat,
  COUNT(*) AS n,
  ROUND(COUNTIF(hospital_expire_flag = 1) * 100.0 / COUNT(*), 2) AS mortality_pct
FROM admissions_with_los awl
JOIN charlson ch ON awl.hadm_id = ch.hadm_id
GROUP BY 1, 2
ORDER BY 
  CASE los_cat WHEN '1-3' THEN 1 WHEN '4-7' THEN 2 ELSE 3 END,
  CASE charlson_cat WHEN '<=3' THEN 1 WHEN '4-5' THEN 2 ELSE 3 END;

-- Query 2: Discharge destination (%) among survivors (overall for cohort)
WITH survivor_cohort AS (
  SELECT a.discharge_location, a.hadm_id
  FROM cohort_hadm c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
  WHERE a.hospital_expire_flag = 0 AND a.dischtime IS NOT NULL
)
SELECT 
  CASE 
    WHEN LOWER(discharge_location) LIKE '%home%' THEN 'home'
    WHEN LOWER(discharge_location) LIKE '%rehab%' THEN 'rehab'
    WHEN LOWER(discharge_location) LIKE '%snf%' OR LOWER(discharge_location) LIKE '%nursing%' THEN 'SNF'
    WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'hospice'
    ELSE 'other'
  END AS destination,
  COUNT(*) AS n,
  ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM survivor_cohort), 2) AS pct
FROM survivor_cohort
GROUP BY 1
ORDER BY pct DESC;

-- Query 3: Mortality (%) by LOS (overall), with absolute and relative differences (long vs. short LOS)
WITH admissions_with_los AS (
  SELECT 
    a.hadm_id,
    a.dischtime,
    a.admittime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM cohort_hadm c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
  WHERE a.dischtime IS NOT NULL
),
los_mort AS (
  SELECT 
    CASE 
      WHEN los_days <= 3 THEN '1-3'
      WHEN los_days <= 7 THEN '4-7'
      ELSE '>=8'
    END AS los_cat,
    COUNT(*) AS n,
    ROUND(COUNTIF(hospital_expire_flag = 1) * 100.0 / COUNT(*), 2) AS mortality_pct
  FROM admissions_with_los
  GROUP BY 1
)
SELECT 
  los_cat,
  n,
  mortality_pct
FROM los_mort
ORDER BY 
  CASE los_cat WHEN '1-3' THEN 1 WHEN '4-7' THEN 2 ELSE 3 END
UNION ALL
SELECT 
  'Abs diff (>=8 vs 1-3)' AS los_cat,
  NULL AS n,
  ROUND(
    (SELECT mortality_pct FROM los_mort WHERE los_cat = '>=8') 
    - (SELECT mortality_pct FROM los_mort WHERE los_cat = '1-3'), 2
  ) AS mortality_pct
UNION ALL
SELECT 
  'Rel risk (>=8 vs 1-3)' AS los_cat,
  NULL AS n,
  ROUND(
    (SELECT mortality_pct FROM los_mort WHERE los_cat = '>=8') 
    / NULLIF((SELECT mortality_pct FROM los_mort WHERE los_cat = '1-3'), 0), 2
  ) AS mortality_pct
ORDER BY 
  CASE 
    WHEN los_cat IN ('Abs diff (>=8 vs 1-3)', 'Rel risk (>=8 vs 1-3)') THEN 4 
    ELSE CASE los_cat WHEN '1-3' THEN 1 WHEN '4-7' THEN 2 ELSE 3 END 
  END;