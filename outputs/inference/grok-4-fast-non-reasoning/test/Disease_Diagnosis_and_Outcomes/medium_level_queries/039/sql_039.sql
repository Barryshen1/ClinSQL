WITH ami_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    p.gender,
    p.anchor_age,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id 
    AND a.subject_id = d.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND 76
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%') 
      OR 
      (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    )
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) >= 1
),
los_bins AS (
  SELECT 
    *,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_bin,
    CASE 
      WHEN admission_type = 'EMERGENCY' THEN 'Emergent'
      ELSE 'Non-emergent'
    END AS adm_type,
    CASE 
      WHEN hospital_expire_flag = 1 AND deathtime IS NOT NULL 
      THEN DATE_DIFF(DATE(deathtime), DATE(admittime), DAY) 
      ELSE NULL 
    END AS time_to_death_days
  FROM ami_admissions
),
mortality_stats AS (
  SELECT 
    los_bin,
    adm_type,
    COUNT(*) AS total_admissions,
    SUM(hospital_expire_flag) AS num_deaths,
    SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS mortality_pct
  FROM los_bins
  GROUP BY los_bin, adm_type
),
timetodeath_stats AS (
  SELECT 
    los_bin,
    adm_type,
    PERCENTILE_CONT(time_to_death_days, 0.5) OVER (PARTITION BY los_bin, adm_type) AS median_ttd_days
  FROM los_bins
  WHERE hospital_expire_flag = 1 AND time_to_death_days IS NOT NULL
)
SELECT 
  m.los_bin,
  m.adm_type,
  m.total_admissions,
  ROUND(m.mortality_pct, 2) AS mortality_pct,
  COALESCE(ANY_VALUE(t.median_ttd_days), 0) AS median_time_to_death_days  -- 0 if no deaths
FROM mortality_stats m
LEFT JOIN timetodeath_stats t
  ON m.los_bin = t.los_bin AND m.adm_type = t.adm_type
GROUP BY m.los_bin, m.adm_type, m.total_admissions, m.mortality_pct
ORDER BY 
  CASE los_bin 
    WHEN '1-3' THEN 1 
    WHEN '4-7' THEN 2 
    ELSE 3 
  END,
  CASE adm_type WHEN 'Emergent' THEN 1 ELSE 2 END
;