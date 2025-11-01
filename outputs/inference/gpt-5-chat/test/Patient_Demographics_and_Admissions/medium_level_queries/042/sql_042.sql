WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    p.gender,
    p.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR)/24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON adm.subject_id = p.subject_id
  -- join to services to identify medicine patients: take first service row
  JOIN (
    SELECT subject_id, hadm_id,
           curr_service,
           ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.services`
  ) AS svc
    ON adm.subject_id = svc.subject_id
   AND adm.hadm_id = svc.hadm_id
   AND svc.rn = 1
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND UPPER(adm.admission_type) != 'ELECTIVE'
    AND UPPER(svc.curr_service) LIKE 'MED%'  -- medicine service
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
),
stats_by_outcome AS (
  SELECT
    hospital_expire_flag,
    AVG(los_days) AS mean_los,
    -- approx_quantiles returns array[101] when num_buckets=100: index for p50=50, p75=75, p90=90
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los
  FROM cohort
  GROUP BY hospital_expire_flag
),
five_day_percentile AS (
  SELECT
    -- proportion of LOS <= 5 days
    AVG(CASE WHEN los_days <= 5 THEN 1.0 ELSE 0.0 END) AS pct_rank_5day
  FROM cohort
)
SELECT
  s.hospital_expire_flag,
  s.mean_los,
  s.p50_los,
  s.p75_los,
  s.p90_los,
  f.pct_rank_5day
FROM stats_by_outcome s
CROSS JOIN five_day_percentile f
ORDER BY s.hospital_expire_flag;