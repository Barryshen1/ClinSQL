WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.anchor_age BETWEEN 88 AND 98
    AND p.gender = 'M'
    AND a.admission_type = 'Elective'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
discharge_outcome AS (
  SELECT
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LTACH', 'HOSPICE', 'REHAB/DISTINCT PART', 'REHAB/OTHER', 'REHAB/INPATIENT', 'REHAB/OTHER FACILITY') THEN 'SNF/rehab/LTACH'
      WHEN discharge_location IN ('HOME', 'HOME WITH HOME CARE', 'HOME WITH HEALTH SERVICES', 'HOME WITH HOSPICE') THEN 'Home'
      ELSE NULL
    END AS discharge_outcome
  FROM
    filtered_admissions
  WHERE
    discharge_location IS NOT NULL
    OR hospital_expire_flag = 1
)
SELECT
  discharge_outcome,
  AVG(los_days) AS mean_los,
  PERCENTILE_CONT(los_days, 0.5) AS median_los_p50,
  PERCENTILE_CONT(los_days, 0.75) AS p75_los,
  PERCENTILE_CONT(los_days, 0.90) AS p90_los,
  AVG(CASE WHEN los_days <= 7 THEN 1.0 ELSE 0.0 END) * 100 AS percent_los_le_7_days
FROM
  discharge_outcome
WHERE
  discharge_outcome IS NOT NULL
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;