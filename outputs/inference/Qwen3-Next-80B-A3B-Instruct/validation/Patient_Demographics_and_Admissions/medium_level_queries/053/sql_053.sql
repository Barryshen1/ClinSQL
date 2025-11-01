WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.admission_type = 'EMERGENCY'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
categorized_discharges AS (
  SELECT
    los_days,
    CASE
      WHEN hospital_expire_flag = '1' THEN 'In-hospital death'
      WHEN discharge_location = 'HOME' THEN 'Discharged home'
      WHEN discharge_location = 'HOSPICE' THEN 'Discharged to hospice'
      ELSE NULL
    END AS discharge_category
  FROM
    filtered_admissions
  WHERE
    CASE
      WHEN hospital_expire_flag = '1' THEN 'In-hospital death'
      WHEN discharge_location = 'HOME' THEN 'Discharged home'
      WHEN discharge_location = 'HOSPICE' THEN 'Discharged to hospice'
      ELSE NULL
    END IS NOT NULL
)
SELECT
  discharge_category,
  PERCENTILE_CONT(los_days, 0.5) AS median_los_days,
  PERCENTILE_CONT(los_days, 0.25) AS iqr_lower,
  PERCENTILE_CONT(los_days, 0.75) AS iqr_upper
FROM
  categorized_discharges
GROUP BY
  discharge_category
ORDER BY
  discharge_category;