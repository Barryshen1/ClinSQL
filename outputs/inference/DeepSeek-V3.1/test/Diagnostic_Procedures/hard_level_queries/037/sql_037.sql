WITH age_calculated AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id, 
    ie.intime, 
    ie.outtime, 
    ie.los,
    p.gender, 
    p.anchor_age, 
    p.anchor_year,
    DATETIME_DIFF(ie.intime, DATETIME(p.anchor_year - p.anchor_age, 1, 1, 0, 0, 0), YEAR) AS age_at_icu,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  WHERE p.gender = 'F'
    AND DATETIME_DIFF(ie.intime, DATETIME(p.anchor_year - p.anchor_age, 1, 1, 0, 0, 0), YEAR) BETWEEN 53 AND 63
),
sepsis_stays AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE 
    (di.icd_version = 9 AND di.icd_code IN ('99591','99592','78552')) 
    OR (di.icd_version = 10 AND (di.icd_code LIKE 'A41%' OR di.icd_code LIKE 'R65%'))
),
procedures_count AS (
  SELECT 
    ac.stay_id,
    ac.age_at_icu,
    ac.hospital_expire_flag,
    ac.los,
    CASE WHEN ss.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS sepsis,
    COUNT(pe.itemid) AS procedure_count
  FROM age_calculated ac
  LEFT JOIN sepsis_stays ss
    ON ac.hadm_id = ss.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON ac.stay_id = pe.stay_id
      AND pe.starttime >= ac.intime 
      AND pe.starttime < DATETIME_ADD(ac.intime, INTERVAL 24 HOUR)
  GROUP BY ac.stay_id, ac.age_at_icu, ac.hospital_expire_flag, ac.los, sepsis
)
SELECT 
  sepsis,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] AS p75_procedures,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(90)] AS p90_procedures,
  AVG(los) AS avg_icu_los,
  AVG(hospital_expire_flag) AS hospital_mortality
FROM procedures_count
GROUP BY sepsis
ORDER BY sepsis;