WITH cohort AS (
  SELECT
    adm.hadm_id,
    adm.discharge_location,
    adm.hospital_expire_flag,
    -- Calculate age at admission (year-only approximation)
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission,
    -- Calculate LOS in fractional days
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND adm.admission_location LIKE 'TRANSFER%'
    -- Age filter: 37-47 inclusive
    AND p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) BETWEEN 37 AND 47
    -- Include only target discharge groups
    AND (
      adm.discharge_location IN ('HOME', 'HOME HEALTH CARE')
      OR adm.discharge_location IN ('SKILLED NURSING FACILITY', 'REHAB/DISTINCT PART HOSP', 'LONG TERM CARE HOSPITAL')
      OR adm.hospital_expire_flag = 1
    )
    AND adm.dischtime IS NOT NULL  -- Ensure valid discharge
)
SELECT
  CASE
    WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'home'
    WHEN discharge_location IN ('SKILLED NURSING FACILITY', 'REHAB/DISTINCT PART HOSP', 'LONG TERM CARE HOSPITAL') 
      THEN 'snf_rehab_ltach'
    WHEN hospital_expire_flag = 1 THEN 'mortality'
  END AS discharge_group,
  COUNT(*) AS n,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90,
  APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS p95,
  (COUNTIF(los_days <= 5) * 100.0) / COUNT(*) AS percentile_rank_5d
FROM cohort
GROUP BY discharge_group
ORDER BY 
  CASE discharge_group
    WHEN 'home' THEN 1
    WHEN 'snf_rehab_ltach' THEN 2
    WHEN 'mortality' THEN 3
  END;