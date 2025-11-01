WITH patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    s.curr_service
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.services s
    ON a.hadm_id = s.hadm_id
  WHERE
    p.gender = 'M'
    AND s.curr_service = 'MED'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.admittime <= a.dischtime
),
filtered_admissions AS (
  SELECT
    *,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM
    patient_admissions
  WHERE
    age_at_admission BETWEEN 59 AND 69
),
discharge_groups AS (
  SELECT
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location LIKE '%HOME%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_category
  FROM
    filtered_admissions
  WHERE
    discharge_location IS NOT NULL OR hospital_expire_flag = 1
)
SELECT
  discharge_category,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  AVG(CASE WHEN los_days <= 10 THEN 1.0 ELSE 0.0 END) AS pct_le_10_days
FROM
  discharge_groups
GROUP BY
  discharge_category
ORDER BY
  discharge_category;