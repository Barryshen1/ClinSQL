WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admission_type,
    adm.hospital_expire_flag,
    adm.discharge_location,
    DATETIME_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 80 AND 90
    AND adm.admission_type != 'EMERGENCY'
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
, dispositioned AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'DEATH'
      WHEN UPPER(discharge_location) LIKE '%HOSPICE%' THEN 'HOSPICE'
      WHEN UPPER(discharge_location) LIKE '%HOME%' THEN 'HOME'
    END AS disposition
  FROM cohort
  WHERE los >= 0
)
SELECT
  disposition,
  COUNT(*) AS n,
  ROUND(AVG(los),2) AS mean_los,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(25)],2) AS p25_los,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(50)],2) AS median_los,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(75)],2) AS p75_los,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(90)],2) AS p90_los,
  ROUND(100 * SUM(CASE WHEN los <= 14 THEN 1 ELSE 0 END) / COUNT(*),2) AS pct_los_le_14
FROM dispositioned
WHERE disposition IS NOT NULL
GROUP BY disposition
ORDER BY disposition;