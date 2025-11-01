WITH filtered_admissions AS (
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
    AND p.anchor_age BETWEEN 78 AND 88
    AND a.admission_type = 'TRANSFER'
)
SELECT
  CASE
    WHEN hospital_expire_flag = 0 THEN 'survived'
    WHEN hospital_expire_flag = 1 THEN 'died'
  END AS outcome,
  COUNT(*) AS count,
  PERCENTILE_CONT(los, 0.5) WITHIN GROUP (ORDER BY los) AS p50,
  PERCENTILE_CONT(los, 0.75) WITHIN GROUP (ORDER BY los) AS p75,
  PERCENTILE_CONT(los, 0.90) WITHIN GROUP (ORDER BY los) AS p90,
  PERCENTILE_CONT(los, 0.95) WITHIN GROUP (ORDER BY los) AS p95,
  (SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percentile_rank_10_days
FROM
  filtered_admissions
GROUP BY
  hospital_expire_flag;