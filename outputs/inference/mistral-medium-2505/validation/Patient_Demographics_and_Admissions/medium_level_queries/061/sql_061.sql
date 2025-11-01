WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 AS length_of_stay,
    CASE
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(a.discharge_location) LIKE '%facility%' THEN 'Facility'
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital Death'
      ELSE 'Other'
    END AS discharge_outcome
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND a.insurance = 'Medicare'
    AND a.admission_type = 'URGENT'
    AND a.dischtime IS NOT NULL
)

SELECT
  discharge_outcome,
  COUNT(*) AS patient_count,
  AVG(length_of_stay) AS mean_los,
  PERCENTILE_CONT(length_of_stay, 0.5) OVER() AS median_los,
  PERCENTILE_CONT(length_of_stay, 0.75) OVER() AS p75_los,
  PERCENTILE_CONT(length_of_stay, 0.9) OVER() AS p90_los,
  -- Calculate percentile rank of 10-day stay
  CASE
    WHEN PERCENTILE_CONT(length_of_stay, 0.5) OVER() <= 10 THEN 0.5
    WHEN PERCENTILE_CONT(length_of_stay, 0.75) OVER() <= 10 THEN 0.75
    WHEN PERCENTILE_CONT(length_of_stay, 0.9) OVER() <= 10 THEN 0.9
    ELSE 1.0
  END AS percentile_rank_10_day
FROM
  filtered_admissions
GROUP BY
  discharge_outcome, length_of_stay
ORDER BY
  discharge_outcome;