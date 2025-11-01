WITH patient_los AS (
  SELECT
    adm.hadm_id,
    p.gender,
    adm.admittime,
    adm.dischtime,
    adm.discharge_location,
    adm.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission,
    -- Calculate length of stay in days
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND adm.admission_type = 'EMERGENCY'
    AND adm.dischtime IS NOT NULL  -- Only completed stays
    AND adm.hospital_expire_flag IS NOT NULL
    AND (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age) BETWEEN 77 AND 87
),
stratified_los AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Discharged Home'
      ELSE 'Other'
    END AS outcome_group
  FROM patient_los
)
SELECT
  outcome_group,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS median_los_days,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS q1_los_days,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS q3_los_days
FROM stratified_los
WHERE outcome_group != 'Other'
GROUP BY outcome_group
ORDER BY outcome_group;