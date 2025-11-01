WITH cohort AS (
  SELECT
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND adm.admission_type = 'ELECTIVE'
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age BETWEEN 44 AND 54
)
SELECT
  hospital_expire_flag,
  COUNT(*) AS n,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90
FROM cohort
GROUP BY hospital_expire_flag
ORDER BY hospital_expire_flag;