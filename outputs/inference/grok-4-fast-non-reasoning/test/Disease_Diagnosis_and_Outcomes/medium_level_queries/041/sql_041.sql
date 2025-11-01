WITH sepsis_cohort AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND p.anchor_age >= 18
    AND (
      -- ICD-10 sepsis codes
      (d.icd_version = '10' AND d.icd_code LIKE 'A41%')
      OR 
      -- ICD-9 sepsis codes (septicemia)
      (d.icd_version = '9' AND (d.icd_code LIKE '038%' OR d.icd_code = '785.52'))
    )
    AND (LOWER(icd.long_title) LIKE '%septic%' OR LOWER(icd.long_title) LIKE '%seps%')
    AND a.admittime < a.dischtime  -- Valid admission
    AND NOT EXISTS (
      -- Exclude if any diagnosis indicates septic shock
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd2
        ON d2.icd_code = icd2.icd_code AND d2.icd_version = icd2.icd_version
      WHERE d2.subject_id = a.subject_id 
        AND d2.hadm_id = a.hadm_id
        AND (
          (d2.icd_version = '10' AND d2.icd_code LIKE 'R65.2%')
          OR 
          (d2.icd_version = '9' AND d2.icd_code = '785.52')  -- Septic shock
        )
        AND (LOWER(icd2.long_title) LIKE '%shock%' OR d2.icd_code LIKE '%shock%')
        AND CAST(a.hospital_expire_flag AS INT64) = 1  -- Fixed: Cast STRING to INT64
    )
)

SELECT 
  los_stratum,
  n_patients,
  mortality_pct,
  -- Absolute difference
  CASE WHEN los_stratum = '≤7' THEN NULL 
       ELSE (mortality_pct - LAG(mortality_pct) OVER (ORDER BY CASE WHEN los_stratum = '≤7' THEN 1 ELSE 2 END)) END AS abs_diff_pct,
  -- Relative difference (safe to avoid div-by-zero)
  CASE WHEN los_stratum = '≤7' THEN NULL 
       ELSE SAFE_DIVIDE((mortality_pct - LAG(mortality_pct) OVER (ORDER BY CASE WHEN los_stratum = '≤7' THEN 1 ELSE 2 END)), LAG(mortality_pct) OVER (ORDER BY CASE WHEN los_stratum = '≤7' THEN 1 ELSE 2 END)) * 100 END AS rel_diff_pct
FROM (
  SELECT 
    CASE WHEN los_days <= 7 THEN '≤7' ELSE '>7' END AS los_stratum,
    COUNT(*) AS n_patients,
    ROUND(SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)) * 100.0, COUNT(*)), 2) AS mortality_pct
  FROM sepsis_cohort
  GROUP BY los_stratum
)
ORDER BY 
  CASE WHEN los_stratum = '≤7' THEN 1 ELSE 2 END;

-- Separate query for median time-to-death (hours from admit to death, for decedents only)
SELECT 
  ROUND(PERCENTILE_CONT(0.5) OVER (ORDER BY time_to_death_hrs), 0) AS median_time_to_death_hrs
FROM (
  SELECT 
    DATE_DIFF(deathtime, admittime, HOUR) AS time_to_death_hrs
  FROM sepsis_cohort
  WHERE CAST(hospital_expire_flag AS INT64) = 1
    AND deathtime IS NOT NULL
);