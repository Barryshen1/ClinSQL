WITH base AS (
  SELECT
    adm.hadm_id,
    adm.subject_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    -- Calculate age at admission
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission,
    -- Calculate LOS in days
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'  -- Male patients
)

SELECT
  CASE
    WHEN hospital_expire_flag = 1 THEN 'Died in Hospital'
    ELSE 'Discharged Alive'
  END AS discharge_status,
  COUNT(*) AS num_admissions,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50,  -- Median
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90,
  -- Percentile rank of 5-day LOS (as percentage)
  (COUNTIF(los <= 5) / COUNT(*)) * 100 AS percentile_rank_5
FROM
  base
WHERE
  age_at_admission BETWEEN 83 AND 93  -- Age filter
GROUP BY
  hospital_expire_flag
ORDER BY
  discharge_status;