WITH patient_los AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit,
    -- Compute LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime  -- valid LOS
    -- Filter age at admission: 89 to 99 inclusive
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 89 AND 99
    -- Non-emergent: exclude EMERGENCY
    AND a.admission_type != 'EMERGENCY'
),
discharge_groups AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    CASE
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location LIKE 'HOSPICE%' THEN 'Hospice'
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      ELSE NULL
    END AS discharge_group
  FROM patient_los
  WHERE discharge_location = 'HOME'
     OR discharge_location LIKE 'HOSPICE%'
     OR hospital_expire_flag = 1
)
SELECT
  discharge_group,
  AVG(los_days) AS mean_los,
  PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY discharge_group) AS median_los,
  PERCENTILE_CONT(los_days, 0.75) OVER (PARTITION BY discharge_group) AS p75_los,
  PERCENTILE_CONT(los_days, 0.90) OVER (PARTITION BY discharge_group) AS p90_los,
  AVG(CASE WHEN los_days < 5 THEN 1.0 ELSE 0.0 END) AS pct_los_lt_5d
FROM discharge_groups
GROUP BY discharge_group, los_days  -- Required for window functions to work with GROUP BY
ORDER BY discharge_group;