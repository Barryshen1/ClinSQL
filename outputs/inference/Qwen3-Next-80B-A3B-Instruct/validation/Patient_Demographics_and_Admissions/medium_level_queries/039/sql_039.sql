WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.anchor_age BETWEEN 37 AND 47
    AND p.gender = 'F'
    AND a.admission_type IN ('URGENT', 'EMERGENCY')
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
discharge_outcome AS (
  SELECT
    los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME WITH HOME CARE', 'HOME WITH HEALTH SERVICES') THEN 'Home'
      WHEN discharge_location LIKE '%SNF%' OR discharge_location LIKE '%REHAB%' OR discharge_location LIKE '%LONG TERM%' 
           OR discharge_location LIKE '%FACILITY%' OR discharge_location IN ('DISCHARGE TO OTHER FACILITY', 'SKILLED NURSING FACILITY', 'OTHER FACILITY') THEN 'Facility'
      ELSE NULL
    END AS discharge_outcome
  FROM
    filtered_admissions
  WHERE
    los IS NOT NULL
)
SELECT
  discharge_outcome,
  AVG(los) AS mean_los,
  PERCENTILE_CONT(los, 0.25) AS p25_los,
  PERCENTILE_CONT(los, 0.5) AS p50_los,
  PERCENTILE_CONT(los, 0.75) AS p75_los,
  AVG(CASE WHEN los <= 7 THEN 1.0 ELSE 0 END) AS percentile_rank_7day
FROM
  discharge_outcome
WHERE
  discharge_outcome IS NOT NULL
GROUP BY
  discharge_outcome
ORDER BY
  1;