WITH base AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE
      WHEN adm.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN adm.discharge_location = 'HOME' THEN 'home'
      ELSE 'facility'
    END AS discharge_outcome
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND adm.admission_type = 'URGENT'  -- Urgent admission
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) 
        BETWEEN 86 AND 96)  -- Age 86-96 at admission
)

SELECT
  discharge_outcome,
  COUNT(*) AS num_admissions,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  AVG(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) * 100 AS pct_10_day_or_less
FROM base
GROUP BY discharge_outcome
ORDER BY discharge_outcome;