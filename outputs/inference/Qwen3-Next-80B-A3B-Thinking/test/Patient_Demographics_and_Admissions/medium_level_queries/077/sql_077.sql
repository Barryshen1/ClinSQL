WITH los_data AS (
  SELECT
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND a.edregtime IS NOT NULL
)
SELECT
  hospital_expire_flag,
  AVG(los) AS mean_los,
  PERCENTILE_CONT(los, 0.5) AS median_los,
  COUNTIF(los <= 5) * 100.0 / COUNT(*) AS percent_5day_los
FROM
  los_data
GROUP BY
  hospital_expire_flag;