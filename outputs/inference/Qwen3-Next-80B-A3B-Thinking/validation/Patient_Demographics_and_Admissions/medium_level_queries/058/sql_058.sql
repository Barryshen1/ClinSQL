WITH filtered_data AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    a.admission_type,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital mortality'
      WHEN a.discharge_location LIKE '%HOME%' THEN 'home'
      WHEN a.discharge_location LIKE '%SNF%' OR a.discharge_location LIKE '%REHAB%' OR a.discharge_location LIKE '%LTACH%' THEN 'SNF/rehab/LTACH'
      ELSE NULL
    END AS discharge_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 37 AND 47
    AND a.admission_type = 'TRANSFER'
    AND a.dischtime IS NOT NULL
)
SELECT
  discharge_category,
  COUNT(*) AS n,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90,
  APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS p95,
  (COUNTIF(los_days <= 5) * 100.0 / COUNT(*)) AS percentile_rank_5_days
FROM filtered_data
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category;