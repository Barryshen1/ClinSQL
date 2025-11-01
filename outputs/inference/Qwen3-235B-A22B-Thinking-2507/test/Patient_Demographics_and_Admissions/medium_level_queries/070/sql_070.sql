WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    a.discharge_location,
    -- Calculate age at admission using MIMIC-IV anchor system
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Calculate LOS in fractional days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND a.admission_location IN ('EMERGENCY ROOM ADMIT', 'TRANSFER FROM HOSPITAL EMERGENCY ROOM')
    AND a.dischtime IS NOT NULL  -- Exclude ongoing admissions
    -- Age filter: 57-67 inclusive at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 57 AND 67
),
discharge_groups AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'HOME' THEN 'Discharged home'
      WHEN discharge_location LIKE 'HOSPICE%' THEN 'Hospice'
      ELSE NULL
    END AS discharge_group
  FROM filtered_admissions
)
SELECT
  discharge_group,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  SAFE_DIVIDE(COUNTIF(los_days <= 10), COUNT(*)) * 100 AS percentile_rank_10
FROM discharge_groups
WHERE discharge_group IS NOT NULL  -- Exclude other discharge types
GROUP BY discharge_group
ORDER BY 
  CASE discharge_group
    WHEN 'Discharged home' THEN 1
    WHEN 'Hospice' THEN 2
    WHEN 'In-hospital death' THEN 3
  END;