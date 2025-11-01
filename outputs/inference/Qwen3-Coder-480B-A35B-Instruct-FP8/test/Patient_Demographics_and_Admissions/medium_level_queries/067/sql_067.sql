WITH cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'DIED_IN_HOSPITAL'
      WHEN a.discharge_location LIKE '%HOSPICE%' THEN 'HOSPICE'
      WHEN a.discharge_location LIKE 'HOME%' THEN 'HOME'
      ELSE 'OTHER'
    END AS discharge_category
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.services s
    ON a.hadm_id = s.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND s.curr_service = 'MED'
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),

grouped_stats AS (
  SELECT
    discharge_category,
    COUNT(*) AS total_patients,
    COUNTIF(los >= 7) AS los_ge_7,
    COUNTIF(los >= 14) AS los_ge_14,
    APPROX_QUANTILES(los, 100)[OFFSET(7)] AS los_7th_percentile
  FROM
    cohort
  WHERE
    discharge_category IN ('HOME', 'HOSPICE', 'DIED_IN_HOSPITAL')
  GROUP BY
    discharge_category
)

SELECT
  discharge_category,
  total_patients,
  ROUND(SAFE_DIVIDE(los_ge_7, total_patients), 4) AS prop_los_ge_7,
  ROUND(SAFE_DIVIDE(los_ge_14, total_patients), 4) AS prop_los_ge_14,
  los_7th_percentile
FROM
  grouped_stats
ORDER BY
  discharge_category;