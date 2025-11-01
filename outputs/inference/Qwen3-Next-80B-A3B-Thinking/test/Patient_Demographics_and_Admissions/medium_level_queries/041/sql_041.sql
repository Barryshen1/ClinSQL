WITH filtered_admissions AS (
  SELECT
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE', 'OTHER') THEN 'Home'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LTACH', 'REHABILITATION', 'SKILLED NURSING FACILITY') THEN 'SNF/rehab/LTACH'
      ELSE NULL
    END AS discharge_outcome
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    a.admission_type = 'ELECTIVE'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 88 AND 98
)
SELECT
  discharge_outcome,
  AVG(los) AS mean_los,
  PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY los) AS median_los,
  PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY los) AS p75_los,
  PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY los) AS p90_los,
  (COUNTIF(los <= 7) * 100.0 / COUNT(*)) AS percent_los_le7
FROM
  filtered_admissions
WHERE
  discharge_outcome IS NOT NULL
GROUP BY
  discharge_outcome;