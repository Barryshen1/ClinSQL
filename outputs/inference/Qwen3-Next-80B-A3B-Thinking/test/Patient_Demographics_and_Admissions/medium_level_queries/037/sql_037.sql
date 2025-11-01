WITH filtered_admissions AS (
  SELECT
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 52 AND 62
    AND a.admission_type != 'Emergency'
    AND a.dischtime IS NOT NULL
)
SELECT
  hospital_expire_flag,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS p50,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los) AS p75,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY los) AS p90,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY los) AS p95,
  AVG(CASE WHEN los <= 7 THEN 1 ELSE 0 END) * 100 AS percentile_rank_7_days
FROM filtered_admissions
GROUP BY hospital_expire_flag;