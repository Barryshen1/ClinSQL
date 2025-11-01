WITH filtered_admissions AS (
  SELECT
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.discharge_location,
    -- Compute age at admission using MIMIC-IV anchor system
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admit,
    -- Calculate LOS in fractional days using DATETIME_DIFF (handles DATETIME type)
    DATETIME_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  -- Exclude ICU stays by ensuring no matching record in icustays
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'M'
    AND icu.stay_id IS NULL  -- Critical: no ICU stay
    -- Filter discharge locations per clinical question
    AND adm.discharge_location IN ('HOME', 'HOME HEALTH CARE', 'HOSPICE', 'DEAD/EXPIRED')
    -- Age filter: 44-54 inclusive
    AND p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) BETWEEN 44 AND 54
),
discharge_groups AS (
  SELECT
    CASE
      WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'home'
      WHEN discharge_location = 'HOSPICE' THEN 'hospice'
      WHEN discharge_location = 'DEAD/EXPIRED' THEN 'death'
    END AS discharge_group,
    los_days
  FROM filtered_admissions
)
SELECT
  discharge_group,
  -- Calculate percentiles using APPROX_QUANTILES (efficient for large datasets)
  APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS p50,  -- 50th percentile
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75,  -- 75th percentile
  APPROX_QUANTILES(los_days, 1000)[OFFSET(900)] AS p90,  -- 90th percentile
  APPROX_QUANTILES(los_days, 1000)[OFFSET(950)] AS p95,  -- 95th percentile
  -- Percentile rank for 7-day stay: % of stays <= 7 days
  ROUND(COUNTIF(los_days <= 7) * 100.0 / COUNT(*), 2) AS percentile_rank_7
FROM discharge_groups
GROUP BY discharge_group
ORDER BY discharge_group;