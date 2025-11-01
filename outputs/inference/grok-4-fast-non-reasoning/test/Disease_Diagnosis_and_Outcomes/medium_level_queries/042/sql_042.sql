WITH ami_cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.gender,
    SAFE_CAST(p.anchor_age AS INT64) AS anchor_age_num,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND SAFE_CAST(p.anchor_age AS INT64) BETWEEN 69 AND 79
    AND p.anchor_age IS NOT NULL
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'I21%'
    AND d.seq_num = 1
    AND a.hospital_expire_flag IN ('0', '1')
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime  -- Ensures LOS >= 1 day
    AND NOT EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_shock
      WHERE d_shock.subject_id = a.subject_id 
        AND d_shock.hadm_id = a.hadm_id
        AND d_shock.icd_version = '10'
        AND d_shock.icd_code = 'R570'
        AND d_shock.seq_num > 0
    )
    AND NOT EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_resp
      WHERE d_resp.subject_id = a.subject_id 
        AND d_resp.hadm_id = a.hadm_id
        AND d_resp.icd_version = '10'
        AND d_resp.icd_code LIKE 'J96%'
        AND d_resp.seq_num > 0
    )
),
los_groups AS (
  SELECT 
    *,
    CASE 
      WHEN los_days <= 3 THEN '1-3 days'
      WHEN los_days <= 7 THEN '4-7 days'
      ELSE '>=8 days'
    END AS los_group
  FROM ami_cohort
  WHERE los_days >= 1  -- Explicit LOS filter
),
summary AS (
  SELECT 
    los_group,
    COUNT(*) AS total_admissions,
    SUM(hospital_expire_flag) AS deaths,
    COUNTIF(hospital_expire_flag = 0) AS survivors,
    PERCENTILE_CONT(0.5, los_days) OVER (PARTITION BY los_group) AS median_los_days
  FROM los_groups
  GROUP BY los_group
),
discharge_counts AS (
  SELECT 
    los_group,
    CASE 
      WHEN discharge_location IN ('HOME', 'SNF', 'REHAB') THEN discharge_location
      ELSE 'OTHER'
    END AS dest_group,
    COUNT(*) AS n
  FROM los_groups
  WHERE hospital_expire_flag = 0 AND discharge_location IS NOT NULL
  GROUP BY los_group, dest_group
)
SELECT 
  s.los_group,
  s.total_admissions,
  ROUND((s.deaths * 100.0 / s.total_admissions), 2) AS mortality_percent,
  ROUND(s.median_los_days, 2) AS median_los_days,
  STRING_AGG(
    dest_group || ': ' || CAST(ROUND((dc.n * 100.0 / s.survivors), 2) AS STRING) || '%', 
    '; '
    ORDER BY dc.n DESC
  ) AS discharge_destinations
FROM summary s
LEFT JOIN discharge_counts dc
  ON s.los_group = dc.los_group
GROUP BY 
  s.los_group, 
  s.total_admissions, 
  s.deaths, 
  s.survivors, 
  s.median_los_days
ORDER BY 
  CASE s.los_group
    WHEN '1-3 days' THEN 1
    WHEN '4-7 days' THEN 2
    ELSE 3
  END;