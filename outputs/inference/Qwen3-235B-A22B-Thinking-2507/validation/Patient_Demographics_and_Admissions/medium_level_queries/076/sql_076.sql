WITH base AS (
  SELECT
    adm.hadm_id,
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / (24 * 60 * 60) AS los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 83 AND 93
)
SELECT
  CASE hospital_expire_flag
    WHEN 0 THEN 'discharged alive'
    WHEN 1 THEN 'in-hospital death'
  END AS status_group,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 1000)[OFFSET(500)] AS median_los,
  APPROX_QUANTILES(los, 1000)[OFFSET(750)] AS p75_los,
  APPROX_QUANTILES(los, 1000)[OFFSET(900)] AS p90_los,
  SAFE_DIVIDE(COUNTIF(los <= 5.0) * 100.0, COUNT(*)) AS pr_5d_percent
FROM base
GROUP BY hospital_expire_flag;