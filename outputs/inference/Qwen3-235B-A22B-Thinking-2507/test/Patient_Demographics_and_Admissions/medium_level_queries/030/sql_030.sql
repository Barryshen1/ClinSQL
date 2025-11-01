WITH filtered_admissions AS (
  SELECT
    adm.hospital_expire_flag,
    -- Calculate age at admission using shifted age per MIMIC-IV privacy
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission,
    -- Compute LOS in fractional days for precision
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / (24 * 60 * 60.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND adm.admission_type = 'ELECTIVE'
    -- Apply age filter (44-54 inclusive) on computed shifted age
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 44 AND 54
    -- Ensure valid timestamps for LOS calculation
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
SELECT
  hospital_expire_flag AS mortality_status,
  COUNT(*) AS n,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS p25_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS p50_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(900)] AS p90_los
FROM filtered_admissions
GROUP BY hospital_expire_flag
ORDER BY hospital_expire_flag;