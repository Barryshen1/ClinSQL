SELECT
  outcome,
  APPROX_QUANTILES(los, 1000)[OFFSET(500)] AS p50,
  APPROX_QUANTILES(los, 1000)[OFFSET(750)] AS p75,
  APPROX_QUANTILES(los, 1000)[OFFSET(900)] AS p90,
  APPROX_QUANTILES(los, 1000)[OFFSET(950)] AS p95,
  COUNTIF(los <= 7) * 100.0 / COUNT(*) AS pct_le7
FROM (
  SELECT 
    icu.los,
    CASE 
      WHEN adm.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN adm.discharge_location = 'Home' THEN 'home'
      WHEN adm.discharge_location LIKE 'Hospice%' THEN 'hospice'
    END AS outcome
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 40 AND 50
    AND (
      adm.hospital_expire_flag = 1 
      OR adm.discharge_location = 'Home'
      OR adm.discharge_location LIKE 'Hospice%'
    )
)
GROUP BY outcome;