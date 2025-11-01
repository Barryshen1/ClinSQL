SELECT
  CASE 
    WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital death'
    ELSE 'Discharged alive'
  END AS survival_status,
  COUNT(*) AS num_icu_stays,
  ROUND(AVG(icu.los), 2) AS mean_los_days,
  ROUND(STDDEV_SAMP(icu.los), 2) AS sd_los_days,
  ROUND(100 * SUM(CASE WHEN icu.los < 7 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_los_lt_7
FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON icu.subject_id = pat.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  ON icu.subject_id = adm.subject_id
  AND icu.hadm_id = adm.hadm_id
WHERE pat.gender = 'F'
  AND pat.anchor_age BETWEEN 35 AND 45
GROUP BY survival_status
ORDER BY survival_status;