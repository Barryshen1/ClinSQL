WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.discharge_location,
    adm.hospital_expire_flag,
    -- Compute age at admission
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_adm,
    -- Compute LOS in integer days
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  WHERE pt.gender = 'M'  -- Male patients
),
med_cohort AS (
  SELECT
    c.*
  FROM cohort c
  WHERE
    c.age_adm BETWEEN 49 AND 59  -- Age 49-59
    AND c.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.services`
      WHERE curr_service = 'MED'  -- Medicine service
    )
),
discharge_groups AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location = 'HOME' THEN 'home'
      WHEN discharge_location IN ('HOSPICE', 'HOSPICE HOME') THEN 'hospice'
      ELSE 'other'
    END AS discharge_group
  FROM med_cohort
),
filtered_cohort AS (
  SELECT *
  FROM discharge_groups
  WHERE discharge_group != 'other'  -- Exclude other discharge locations
)
SELECT
  discharge_group,
  COUNT(*) AS total_patients,
  SAFE_DIVIDE(COUNTIF(los_days >= 7), COUNT(*)) AS proportion_los_ge7,
  SAFE_DIVIDE(COUNTIF(los_days >= 14), COUNT(*)) AS proportion_los_ge14,
  APPROX_QUANTILES(los_days, 100)[OFFSET(7)] AS los_7th_percentile
FROM filtered_cohort
GROUP BY discharge_group
ORDER BY discharge_group;