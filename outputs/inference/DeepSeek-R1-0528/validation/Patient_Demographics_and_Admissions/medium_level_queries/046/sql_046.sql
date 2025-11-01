WITH base AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.discharge_location,
    a.hospital_expire_flag,
    a.admittime,
    a.dischtime,
    p.anchor_year - p.anchor_age AS birth_year,
    MIN(icu.intime) AS first_icu_intime  -- First ICU stay in the admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.hadm_id = icu.hadm_id
  WHERE 
    p.gender = 'F'  -- Females only
  GROUP BY 
    a.subject_id, a.hadm_id, a.discharge_location, 
    a.hospital_expire_flag, a.admittime, a.dischtime, 
    p.anchor_year, p.anchor_age
),
cohort AS (
  SELECT 
    *,
    EXTRACT(YEAR FROM first_icu_intime) - birth_year AS age_at_icu,
    DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0 AS hospital_los_days
  FROM base
  WHERE 
    EXTRACT(YEAR FROM first_icu_intime) - birth_year 
    BETWEEN 87 AND 97  -- Age 87–97 at first ICU stay
),
discharge_groups AS (
  SELECT 
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'HOME' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_group,
    hospital_los_days
  FROM cohort
)
SELECT 
  discharge_group,
  COUNT(*) AS n,
  ROUND(AVG(hospital_los_days), 2) AS mean_los_days,
  ROUND(STDDEV(hospital_los_days), 2) AS sd_los_days,
  ROUND(100 * AVG(CASE WHEN hospital_los_days < 10 THEN 1 ELSE 0 END), 2) AS pct_los_under_10_days
FROM discharge_groups
GROUP BY discharge_group
ORDER BY discharge_group;