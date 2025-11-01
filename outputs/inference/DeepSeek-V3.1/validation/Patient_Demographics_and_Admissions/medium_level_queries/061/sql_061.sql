WITH cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.insurance,
    adm.admission_type,
    adm.discharge_location,
    adm.hospital_expire_flag,
    pat.gender,
    pat.anchor_age,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE 
      WHEN adm.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN adm.discharge_location = 'HOME' THEN 'home'
      ELSE 'facility'
    END AS discharge_outcome
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 86 AND 96
    AND adm.admission_type = 'URGENT'
    AND adm.insurance = 'Medicare'
    AND adm.dischtime > adm.admittime
),

stats AS (
  SELECT
    discharge_outcome,
    COUNT(*) AS n_stays,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
    AVG(CASE WHEN los_days <= 10 THEN 1.0 ELSE 0.0 END) AS percentile_10_day_stay
  FROM cohort
  GROUP BY discharge_outcome
)

SELECT *
FROM stats
ORDER BY discharge_outcome;