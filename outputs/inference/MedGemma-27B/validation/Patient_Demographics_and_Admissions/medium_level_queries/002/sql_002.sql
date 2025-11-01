WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admittime >= '2100-01-01' -- Filter out future dates if any
),
LOSDistribution AS (
  SELECT
    discharge_location,
    hospital_expire_flag,
    AVG(los) AS mean_los,
    APPROX_QUANTILES(los, 4) AS percentiles,
    COUNTIF(los <= 10) / COUNT(*) AS percent_le_10_days
  FROM PatientCohort
  GROUP BY
    discharge_location,
    hospital_expire_flag
)
SELECT
  discharge_location,
  hospital_expire_flag,
  mean_los,
  percentiles[OFFSET(0)] AS p25,
  percentiles[OFFSET(1)] AS p50,
  percentiles[OFFSET(2)] AS p75,
  percentiles[OFFSET(3)] AS p90,
  percent_le_10_days
FROM LOSDistribution
ORDER BY
  discharge_location,
  hospital_expire_flag;