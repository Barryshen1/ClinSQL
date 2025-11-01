WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.dischtime,
    a.admittime,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'death'
      WHEN a.discharge_location = 'Hospice' THEN 'hospice'
      WHEN a.discharge_location = 'Home' THEN 'home'
      ELSE NULL
    END AS discharge_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE
    i.stay_id IS NULL
    AND p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 44 AND 54
    AND a.dischtime IS NOT NULL
)
SELECT
  discharge_category,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90,
  APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95,
  (COUNTIF(los <= 7) * 100.0) / COUNT(*) AS percentile_rank_7day
FROM filtered_admissions
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category;