WITH cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.discharge_location,
    adm.hospital_expire_flag,
    -- Calculate age at admission: from anchor_year and anchor_age
    DATE_DIFF(DATE(adm.admittime), DATE(pat.anchor_year - pat.anchor_age, 1, 1), YEAR) AS age_admit,
    -- Calculate LOS in days (ensure non-negative)
    GREATEST(0, DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR)) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND adm.admission_location LIKE '%EMERGENCY ROOM%'
    -- Filter for admissions with valid times
    AND adm.admittime IS NOT NULL 
    AND adm.dischtime IS NOT NULL
),

-- Categorize discharge outcome
cohort_with_outcome AS (
  SELECT *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'DEATH'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'HOSPICE'
      ELSE 'HOME'
    END AS discharge_outcome
  FROM cohort
  WHERE age_admit BETWEEN 50 AND 60
)

-- Aggregate by discharge outcome
SELECT 
  discharge_outcome,
  COUNT(*) AS n_patients,
  AVG(los_days) AS mean_los_days,
  STDDEV(los_days) AS sd_los_days,
  -- Percentage with LOS <= 10 days
  100.0 * SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*) AS pct_los_leq_10
FROM cohort_with_outcome
GROUP BY discharge_outcome
ORDER BY discharge_outcome;