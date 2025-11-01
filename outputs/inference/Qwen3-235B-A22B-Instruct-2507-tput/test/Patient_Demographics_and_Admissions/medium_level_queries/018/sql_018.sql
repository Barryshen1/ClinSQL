WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Calculate age at admission
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
    -- Calculate LOS in days as a decimal
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24.0 * 60.0 * 60.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND a.admission_type = 'TRANSFER'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 43 AND 53
),
discharge_groups AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_group
  FROM patient_admissions
  WHERE los_days >= 0  -- Ensure valid LOS
)
SELECT
  discharge_group,
  -- Median and IQR
  APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS median_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS q1_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS q3_los,
  -- Percent with LOS <= 10 days
  AVG(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) * 100 AS percent_los_le_10
FROM discharge_groups
WHERE discharge_group IS NOT NULL
GROUP BY discharge_group
ORDER BY discharge_group;