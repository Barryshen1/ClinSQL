WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.gender,
    SAFE_CAST(p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS INT64) AS age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN (
    SELECT 
      hadm_id, 
      curr_service
    FROM `physionet-data.mimiciv_3_1_hosp.services`
    WHERE prev_service IS NULL
  ) s 
    ON a.hadm_id = s.hadm_id
  WHERE p.gender = 'M'
    AND a.admission_type != 'ELECTIVE'
    AND s.curr_service = 'MEDICINE'
    AND SAFE_CAST(p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS INT64) BETWEEN 57 AND 67
    AND a.dischtime > a.admittime
),
stats AS (
  SELECT 
    CASE 
      WHEN hospital_expire_flag = 0 THEN 'Discharged Alive' 
      ELSE 'In-hospital Death' 
    END AS outcome,
    AVG(los) AS mean_los,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50_los,
    APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los
  FROM cohort
  GROUP BY hospital_expire_flag
),
overall_perc AS (
  SELECT 
    (COUNTIF(los <= 5) * 100.0 / COUNT(*)) AS perc_5day_rank
  FROM cohort
)
SELECT 
  s.outcome,
  s.mean_los,
  s.p50_los,
  s.p75_los,
  s.p90_los,
  ROUND(o.perc_5day_rank, 2) AS perc_5day_rank_overall
FROM stats s
CROSS JOIN overall_perc o
ORDER BY 
  CASE outcome 
    WHEN 'Discharged Alive' THEN 1 
    ELSE 2 
  END;