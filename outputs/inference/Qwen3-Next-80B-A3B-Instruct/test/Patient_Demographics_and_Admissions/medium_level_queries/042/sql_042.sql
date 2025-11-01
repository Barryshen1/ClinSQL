WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    a.admission_type,
    s.curr_service
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.services s
    ON a.hadm_id = s.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.admission_type != 'ELECTIVE'
    AND s.curr_service = 'MED'
),
los_calc AS (
  SELECT
    hospital_expire_flag,
    EXTRACT(DAY FROM (dischtime - admittime)) AS los_days
  FROM
    filtered_admissions
  WHERE
    dischtime IS NOT NULL
    AND admittime IS NOT NULL
)
SELECT
  hospital_expire_flag,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS percentile_rank_5day
FROM
  los_calc
GROUP BY
  hospital_expire_flag
ORDER BY
  hospital_expire_flag;