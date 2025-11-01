WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Approximate age at admission
    SAFE_CAST(p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS INT64) AS age_approx
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND SAFE_CAST(p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS INT64) BETWEEN 50 AND 60
),
sepsis_cohort AS (
  SELECT 
    c.*
  FROM 
    cohort c
  WHERE 
    -- Has sepsis diagnosis (not shock in title)
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.subject_id = c.subject_id 
        AND d.hadm_id = c.hadm_id
        AND LOWER(dd.long_title) LIKE '%sepsis%' 
        AND LOWER(dd.long_title) NOT LIKE '%shock%'
    )
    -- No septic shock diagnosis anywhere
    AND NOT EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.subject_id = c.subject_id 
        AND d.hadm_id = c.hadm_id
        AND LOWER(dd.long_title) LIKE '%septic shock%'
    )
)
SELECT 
  CASE 
    WHEN los_days <= 7 THEN '<=7 days'
    ELSE '>7 days'
  END AS los_group,
  CASE 
    WHEN icu_day1 = 1 THEN 'Yes'
    ELSE 'No'
  END AS day1_icu_status,
  COUNT(*) AS n_admissions,
  SUM(hospital_expire_flag) AS n_deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_pct,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days
FROM (
  SELECT 
    s.*,
    -- Day-1 ICU flag
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.hadm_id = s.hadm_id 
          AND i.intime <= TIMESTAMP_ADD(s.admittime, INTERVAL 1 DAY)
      ) THEN 1 
      ELSE 0 
    END AS icu_day1
  FROM 
    sepsis_cohort s
)
GROUP BY 
  los_group, 
  day1_icu_status
ORDER BY 
  los_group, 
  day1_icu_status;