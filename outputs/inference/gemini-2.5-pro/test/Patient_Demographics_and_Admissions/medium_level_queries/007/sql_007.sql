WITH filtered_admissions AS (
  SELECT
    adm.hadm_id,
    adm.hospital_expire_flag,
    -- Calculate LOS in fractional days for higher precision in percentile calculations
    DATETIME_DIFF(adm.dischtime, adm.admittime, SECOND) / (24.0 * 60 * 60) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    -- Filter 1: Male patients
    pat.gender = 'M'
    -- Filter 2: Age at admission between 78 and 88
    AND (
      pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year
    ) BETWEEN 78 AND 88
    -- Filter 3: Transferred from another hospital
    AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
    -- Ensure valid LOS calculation
    AND adm.dischtime >= adm.admittime
)
SELECT
  -- Stratify by survival status for readability
  CASE
    WHEN hospital_expire_flag = 1 THEN 'In-hospital Death'
    ELSE 'Survived'
  END AS outcome,
  -- Report number of admissions in the group
  COUNT(hadm_id) AS number_of_admissions,
  -- Calculate LOS percentiles using an approximate method for performance
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS los_days_p50,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS los_days_p75,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS los_days_p90,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(95)], 2) AS los_days_p95,
  -- Calculate the percentile rank of a 10-day LOS, i.e., the proportion of stays <= 10 days
  ROUND(SAFE_DIVIDE(
    COUNTIF(los_days <= 10),
    COUNT(hadm_id)
  ), 4) AS percentile_rank_of_10_day_los
FROM
  filtered_admissions
GROUP BY
  outcome
ORDER BY
  outcome DESC;