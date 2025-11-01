WITH cohort AS (
  SELECT 
    adm.hadm_id,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE 
      WHEN adm.hospital_expire_flag = 1 THEN 'Died in hospital' 
      ELSE 'Discharged alive' 
    END AS survival_status
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 35 AND 45
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
      WHERE adm.hadm_id = icu.hadm_id
    )
)

SELECT 
  survival_status,
  COUNT(*) AS total_admissions,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS sd_los,
  COUNTIF(los_days < 7) AS count_short_stay,
  (COUNTIF(los_days < 7) * 100.0) / COUNT(*) AS percent_short_stay
FROM cohort
GROUP BY survival_status;