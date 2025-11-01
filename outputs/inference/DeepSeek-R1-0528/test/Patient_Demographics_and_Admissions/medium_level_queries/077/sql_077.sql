WITH base AS (
  SELECT
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year BETWEEN 41 AND 51
    AND adm.admission_location LIKE '%EMERGENCY%'
    AND adm.dischtime >= adm.admittime
)
SELECT
  CASE hospital_expire_flag
    WHEN 1 THEN 'Died in hospital'
    ELSE 'Discharged alive'
  END AS outcome_group,
  COUNT(*) AS num_patients,
  ROUND(AVG(los_days), 2) AS mean_los,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,
  ROUND(COUNTIF(los_days <= 5) / COUNT(*) * 100, 2) AS pct_lte_5_days
FROM base
GROUP BY hospital_expire_flag
ORDER BY hospital_expire_flag DESC;