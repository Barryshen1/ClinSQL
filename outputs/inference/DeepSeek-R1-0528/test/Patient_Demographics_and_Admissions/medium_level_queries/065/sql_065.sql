WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.discharge_location,
    adm.hospital_expire_flag,
    -- Calculate fractional length of stay in days
    CAST(DATETIME_DIFF(adm.dischtime, adm.admittime, SECOND) AS FLOAT64) / 86400.0 AS los_days,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  -- Exclude admissions with any ICU stay
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'F'
    AND icu.stay_id IS NULL  -- Ensure no ICU stay
)
SELECT
  CASE
    WHEN hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
    WHEN discharge_location = 'HOSPICE' THEN 'Discharged to Hospice'
    WHEN discharge_location = 'HOME' THEN 'Discharged Home'
  END AS discharge_category,
  COUNT(*) AS num_admissions,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS sd_los
FROM cohort
WHERE
  age_at_admission BETWEEN 75 AND 85
  AND (  -- Include only the three target categories
    hospital_expire_flag = 1
    OR discharge_location IN ('HOSPICE', 'HOME')
  )
GROUP BY discharge_category;