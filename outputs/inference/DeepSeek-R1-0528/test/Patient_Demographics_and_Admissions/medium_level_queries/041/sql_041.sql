WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.admission_type,
    a.dischtime,
    a.admittime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Calculate LOS in days
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    -- Define discharge outcome groups
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN a.discharge_location = 'HOME' THEN 'Home'
      WHEN a.discharge_location IN (
        'SKILLED NURSING FACILITY', 'REHAB', 'CHRONIC/LONG TERM ACUTE CARE'
      ) THEN 'SNF/rehab/LTACH'
    END AS discharge_outcome
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    -- Age 88-98 at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 88 AND 98
    AND a.admission_type = 'ELECTIVE'  -- Elective admissions only
)

SELECT
  discharge_outcome,
  COUNT(*) AS num_patients,
  AVG(los) AS mean_los,
  -- Percentiles (p50 = median)
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los,
  -- Percentage with LOS <= 7 days
  COUNTIF(los <= 7) * 100.0 / COUNT(*) AS percent_los_leq_7
FROM
  cohort
WHERE
  discharge_outcome IS NOT NULL  -- Exclude other discharge locations
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;