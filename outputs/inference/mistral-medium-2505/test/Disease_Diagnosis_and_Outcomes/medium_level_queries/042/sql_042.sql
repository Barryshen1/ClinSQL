WITH
-- Define AMI and exclusion ICD codes
icd_codes AS (
  SELECT
    icd_code,
    icd_version,
    long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'  -- AMI codes
    OR icd_code LIKE 'R57%'  -- Shock codes
    OR icd_code LIKE 'J96%'  -- Respiratory failure codes
),

-- Get patient admissions with AMI and exclusion criteria
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    MAX(CASE WHEN d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' THEN 1 ELSE 0 END) AS has_ami,
    MAX(CASE WHEN d.icd_code LIKE 'R57%' OR d.icd_code LIKE 'J96%' THEN 1 ELSE 0 END) AS has_exclusion
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 69 AND 79
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.discharge_location, a.hospital_expire_flag, p.gender, p.anchor_age
),

-- Filter for patients with AMI and without exclusion criteria
filtered_patients AS (
  SELECT
    *
  FROM
    patient_admissions
  WHERE
    has_ami = 1
    AND has_exclusion = 0
),

-- Categorize LOS into groups
los_categories AS (
  SELECT
    hadm_id,
    subject_id,
    los_days,
    hospital_expire_flag,
    discharge_location,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN los_days >= 8 THEN '8+ days'
      ELSE 'Other'
    END AS los_category
  FROM
    filtered_patients
  WHERE
    los_days IS NOT NULL
),

-- Get most common discharge locations per LOS category
discharge_stats AS (
  SELECT
    los_category,
    ARRAY_AGG(discharge_location ORDER BY COUNT(*) DESC LIMIT 3) AS common_discharge_locations
  FROM
    los_categories
  GROUP BY
    los_category
)

-- Final aggregation
SELECT
  lc.los_category,
  COUNT(*) AS total_patients,
  SUM(CAST(lc.hospital_expire_flag AS INT64)) AS deaths,
  ROUND(SUM(CAST(lc.hospital_expire_flag AS INT64)) * 100.0 / COUNT(*), 2) AS mortality_percentage,
  ROUND(APPROX_QUANTILES(lc.los_days, 100)[OFFSET(50)], 2) AS median_los,
  ds.common_discharge_locations
FROM
  los_categories lc
JOIN
  discharge_stats ds ON lc.los_category = ds.los_category
GROUP BY
  lc.los_category, ds.common_discharge_locations
ORDER BY
  CASE lc.los_category
    WHEN '1-3 days' THEN 1
    WHEN '4-7 days' THEN 2
    WHEN '8+ days' THEN 3
    ELSE 4
  END;