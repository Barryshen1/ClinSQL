WITH base AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit,
    -- Calculate LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
filtered AS (
  SELECT 
    hadm_id,
    discharge_location,
    hospital_expire_flag,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location = 'HOME' THEN 'home'
      WHEN discharge_location IN ('SKILLED NURSING FACILITY', 'REHAB', 'LONG TERM CARE HOSPITAL') THEN 'SNF/rehab/LTACH'
      ELSE NULL
    END AS discharge_group
  FROM base
  WHERE age_at_admit BETWEEN 64 AND 74
)
SELECT
  discharge_group,
  COUNT(*) AS total_patients,
  COUNTIF(los_days >= 7) AS count_ge7,
  SAFE_DIVIDE(COUNTIF(los_days >= 7), COUNT(*)) AS proportion_ge7,
  APPROX_QUANTILES(los_days, 100)[OFFSET(14)] AS p14_los
FROM filtered
WHERE discharge_group IS NOT NULL
GROUP BY discharge_group;