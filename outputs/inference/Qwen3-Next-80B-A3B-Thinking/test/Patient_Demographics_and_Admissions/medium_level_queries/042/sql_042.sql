WITH cohort AS (
  SELECT
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND a.admission_type != 'ELECTIVE'
    AND p.anchor_age BETWEEN 57 AND 67
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.services` s
      WHERE s.hadm_id = a.hadm_id
        AND s.curr_service = 'MED'
    )
)
SELECT
  hospital_expire_flag,
  AVG(los) AS mean_los,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median_los,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los) AS p75_los,
  PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY los) AS p90_los,
  (SELECT SUM(CASE WHEN los <= 5 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)
   FROM cohort) AS percentile_5_day
FROM cohort
GROUP BY hospital_expire_flag;