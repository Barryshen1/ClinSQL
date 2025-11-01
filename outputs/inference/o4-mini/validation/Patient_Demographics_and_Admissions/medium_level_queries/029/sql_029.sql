SELECT
  CASE
    WHEN adm.hospital_expire_flag = 1 THEN 'in_hospital_death'
    ELSE 'discharged_alive'
  END AS survival_status,
  COUNT(*) AS n_icustays,
  AVG(ic.los) AS mean_los,
  STDDEV_POP(ic.los) AS sd_los,
  100 * SAFE_DIVIDE(COUNTIF(ic.los < 7), COUNT(*)) AS pct_los_lt_7_days
FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON ic.subject_id = adm.subject_id
  AND ic.hadm_id      = adm.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON ic.subject_id = pat.subject_id
WHERE pat.gender = 'F'
  AND pat.anchor_age BETWEEN 35 AND 45
GROUP BY 1
ORDER BY 1;