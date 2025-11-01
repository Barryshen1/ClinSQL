WITH
-- Get relevant patient admissions with age, gender, and transfer info
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    MAX(CASE WHEN a.admission_location = 'HOSPITAL' THEN 1 ELSE 0 END) AS is_transferred
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.discharge_location, a.hospital_expire_flag, p.anchor_age, p.gender
),

-- Filter for transferred patients and calculate LOS
transferred_patients AS (
  SELECT
    subject_id,
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location LIKE '%HOME%' THEN 'Home'
      WHEN discharge_location LIKE '%FACILITY%' THEN 'Facility'
      ELSE 'Other'
    END AS discharge_category
  FROM
    patient_admissions
  WHERE
    is_transferred = 1
    AND dischtime IS NOT NULL
    AND admittime IS NOT NULL
)

-- Calculate statistics by discharge category
SELECT
  discharge_category,
  COUNT(*) AS patient_count,
  APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS median_los,
  APPROX_QUANTILES(los_days, 4)[OFFSET(0)] AS q1_los,
  APPROX_QUANTILES(los_days, 4)[OFFSET(2)] - APPROX_QUANTILES(los_days, 4)[OFFSET(0)] AS iqr_los,
  ROUND(100 * SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*), 1) AS percent_le_10_days
FROM
  transferred_patients
GROUP BY
  discharge_category
ORDER BY
  discharge_category;