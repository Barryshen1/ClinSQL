WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.gender,
    p.anchor_age,
    -- LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.admission_location LIKE 'TRANSFER%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
cohort_grouped AS (
  SELECT
    subject_id,
    hadm_id,
    los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Mortality'
      WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Home'
      WHEN discharge_location IN (
        'SKILLED NURSING FACILITY',
        'REHABILITATION FACILITY',
        'LONG TERM ACUTE CARE HOSPITAL'
      ) THEN 'SNF/REHAB/LTACH'
      ELSE 'Other'
    END AS discharge_group
  FROM cohort
)
SELECT
  discharge_group,
  COUNT(*) AS n,
  ROUND(AVG(los), 2) AS mean_los,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(25)], 2) AS p25,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(50)], 2) AS median,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(75)], 2) AS p75,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(90)], 2) AS p90,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(95)], 2) AS p95,
  ROUND(100 * SUM(CASE WHEN los <= 5 THEN 1 ELSE 0 END) / COUNT(*), 1)
    AS percentile_rank_5day
FROM cohort_grouped
WHERE discharge_group IN ('Home', 'SNF/REHAB/LTACH', 'Mortality')
GROUP BY discharge_group;