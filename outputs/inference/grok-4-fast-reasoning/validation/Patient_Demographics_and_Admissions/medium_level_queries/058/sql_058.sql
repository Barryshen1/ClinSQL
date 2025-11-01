WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    a.admission_location,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND a.admission_location = 'TRANSFER'
    AND 37 <= (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) <= 47
    AND a.dischtime > a.admittime
),
categorized AS (
  SELECT *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital mortality'
      WHEN discharge_location IN (
        'Discharged to home',
        'Discharged to home with home health service'
      ) THEN 'home'
      WHEN discharge_location IN (
        'Discharged to skilled nursing facility',
        'Discharged to rehabilitation',
        'Discharged to long term care hospital'
      ) THEN 'SNF/rehab/LTACH'
      ELSE NULL
    END AS discharge_cat
  FROM cohort
)
SELECT
  discharge_cat,
  COUNT(*) AS n,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90,
  APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95,
  SAFE_DIVIDE(COUNTIF(los <= 5), COUNT(*)) * 100 AS percentile_rank_5_day
FROM categorized
WHERE discharge_cat IS NOT NULL
GROUP BY discharge_cat
ORDER BY discharge_cat;