WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type = 'EMERGENCY'
),
LOSCalculation AS (
  SELECT
    subject_id,
    discharge_location,
    hospital_expire_flag,
    -- Calculate Length of Stay (LOS) in days
    -- Use TIMESTAMP_DIFF for accurate day calculation
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
  FROM PatientInfo
)
SELECT
  discharge_location,
  hospital_expire_flag,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los, -- Use APPROX_QUANTILES for median
  APPROX_QUANTILES(los, 4)[OFFSET(3)] AS p75_los, -- Use APPROX_QUANTILES for p75
  APPROX_QUANTILES(los, 10)[OFFSET(9)] AS p90_los, -- Use APPROX_QUANTILES for p90
  PERCENTILE_CONT(los, 0.07) AS percentile_rank_7_days
FROM LOSCalculation
GROUP BY
  discharge_location,
  hospital_expire_flag
ORDER BY
  discharge_location,
  hospital_expire_flag;