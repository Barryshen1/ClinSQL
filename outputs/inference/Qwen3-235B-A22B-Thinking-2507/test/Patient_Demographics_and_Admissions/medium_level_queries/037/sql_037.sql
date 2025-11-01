WITH cohort AS (
  SELECT
    adm.hospital_expire_flag,
    -- Calculate age at admission per MIMIC documentation
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_adm,
    -- Calculate LOS in fractional days
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND adm.admission_type = 'ELECTIVE'  -- Strict non-emergency = elective
    AND adm.dischtime IS NOT NULL  -- Only discharged patients
    -- Age filter: 52-62 inclusive
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 52 AND 62
)
SELECT
  CASE hospital_expire_flag
    WHEN 0 THEN 'discharged alive'
    WHEN 1 THEN 'in-hospital death'
  END AS outcome_group,
  -- Extract precise percentiles from quantiles array
  APPROX_QUANTILES(los_days, 10000)[OFFSET(5000)] AS p50,
  APPROX_QUANTILES(los_days, 10000)[OFFSET(7500)] AS p75,
  APPROX_QUANTILES(los_days, 10000)[OFFSET(9000)] AS p90,
  APPROX_QUANTILES(los_days, 10000)[OFFSET(9500)] AS p95,
  -- Calculate percentile rank for 7-day LOS
  (COUNTIF(los_days <= 7) * 100.0) / COUNT(*) AS percentile_rank_7
FROM cohort
GROUP BY hospital_expire_flag
ORDER BY hospital_expire_flag;