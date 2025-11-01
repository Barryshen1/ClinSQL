WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND a.admission_type = 'URGENT'
    AND a.insurance = 'Medicare'
    AND a.dischtime IS NOT NULL
),
categorized_outcomes AS (
  SELECT
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME WITH HOME CARE', 'HOME WITH HEALTH SERVICES', 'HOME WITH HOSPICE') THEN 'home'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LONG TERM CARE', 'OTHER FACILITY', 'FACILITY', 'SKILLED NURSING FACILITY') THEN 'facility'
      ELSE NULL
    END AS discharge_outcome
  FROM
    filtered_admissions
)
SELECT
  discharge_outcome,
  AVG(los_days) AS mean_los,
  PERCENTILE_DISC(los_days, 0.5) WITHIN GROUP (ORDER BY los_days) AS median_los,
  PERCENTILE_DISC(los_days, 0.75) WITHIN GROUP (ORDER BY los_days) AS p75_los,
  PERCENTILE_DISC(los_days, 0.90) WITHIN GROUP (ORDER BY los_days) AS p90_los,
  AVG(CASE WHEN los_days <= 10 THEN 1.0 ELSE 0 END) * 100 AS percentile_of_10day_stay
FROM
  categorized_outcomes
WHERE
  discharge_outcome IS NOT NULL
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;