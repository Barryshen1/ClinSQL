WITH cohort AS (
  SELECT
    adm.hadm_id,
    adm.discharge_location,
    -- Calculate age at admission using MIMIC-IV anchor method
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission,
    -- Compute LOS in fractional days (seconds → days)
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / (24 * 60 * 60) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON adm.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND adm.admission_type = 'ELECTIVE'  -- Non-emergent = ELECTIVE
    AND adm.dischtime IS NOT NULL        -- Exclude ongoing admissions
    AND adm.dischtime >= adm.admittime   -- Ensure valid LOS
)
SELECT
  CASE
    WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'home'
    WHEN discharge_location IN ('HOSPICE', 'HOSPICE-HOME', 'HOSPICE-MEDICAL FACILITY') THEN 'hospice'
    WHEN discharge_location = 'DEAD/EXPIRED' THEN 'in-hospital death'
  END AS discharge_category,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 1000)[OFFSET(500)] AS median_los,
  APPROX_QUANTILES(los, 1000)[OFFSET(750)] AS p75_los,
  APPROX_QUANTILES(los, 1000)[OFFSET(900)] AS p90_los,
  (COUNTIF(los < 5) * 100.0) / COUNT(*) AS percent_los_lt5
FROM cohort
WHERE
  age_at_admission BETWEEN 89 AND 99  -- Age 89-99 inclusive
  AND discharge_location IN ('HOME', 'HOME HEALTH CARE', 'HOSPICE', 'HOSPICE-HOME', 'HOSPICE-MEDICAL FACILITY', 'DEAD/EXPIRED')
GROUP BY discharge_category
ORDER BY discharge_category;