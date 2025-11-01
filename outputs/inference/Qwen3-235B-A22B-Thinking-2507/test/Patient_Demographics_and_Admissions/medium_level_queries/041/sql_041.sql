WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    -- Calculate age at admission per MIMIC-IV documentation
    p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND a.admission_type = 'ELECTIVE'
    AND (p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime))) BETWEEN 88 AND 98
),
filtered AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    discharge_location,
    -- Define discharge outcome categories
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location = 'HOME' THEN 'home'
      WHEN discharge_location IN (
        'SKILLED NURSING FACILITY', 
        'REHAB', 
        'REHABILITATION',
        'REHAB - HOSPICE',
        'REHAB/DISTINCT PART HOSP',
        'LONG TERM CARE HOSPITAL'
      ) THEN 'SNF/rehab/LTACH'
      ELSE NULL 
    END AS discharge_outcome,
    -- Calculate LOS in fractional days
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / (24*60*60) AS los_days
  FROM cohort
  WHERE 
    -- Filter to only the three required outcome types
    hospital_expire_flag = 1 
    OR discharge_location = 'HOME'
    OR discharge_location IN (
      'SKILLED NURSING FACILITY', 
      'REHAB', 
      'REHABILITATION',
      'REHAB - HOSPICE',
      'REHAB/DISTINCT PART HOSP',
      'LONG TERM CARE HOSPITAL'
    )
)
SELECT 
  discharge_outcome,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS p50,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(900)] AS p90,
  COUNTIF(los_days <= 7) * 100.0 / COUNT(*) AS percent_los_le7
FROM filtered
GROUP BY discharge_outcome
ORDER BY discharge_outcome;