WITH female_emergency_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS length_of_stay_days,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS admission_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_type = 'EMERGENCY'
    AND a.dischtime IS NOT NULL
),
filtered_admissions AS (
  SELECT * FROM female_emergency_admissions
  WHERE admission_age BETWEEN 77 AND 87
),
admissions_with_discharge_category AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location LIKE '%Hospice%' THEN 'Hospice'
      WHEN discharge_location LIKE '%Home%' THEN 'Home'
      ELSE 'Other'
    END AS discharge_category
  FROM
    filtered_admissions
)

SELECT
  discharge_category,
  COUNT(*) AS patient_count,
  ROUND(PERCENTILE_CONT(length_of_stay_days, 0.5), 2) AS median_los_days,
  ROUND(PERCENTILE_CONT(length_of_stay_days, 0.25), 2) AS q1_los_days,
  ROUND(PERCENTILE_CONT(length_of_stay_days, 0.75), 2) AS q3_los_days,
  ROUND(PERCENTILE_CONT(length_of_stay_days, 0.75) -
        PERCENTILE_CONT(length_of_stay_days, 0.25), 2) AS iqr_los_days
FROM
  admissions_with_discharge_category
GROUP BY
  discharge_category
ORDER BY
  discharge_category;