WITH target_cohort AS (
  SELECT 
    ie.subject_id, ie.hadm_id, ie.stay_id,
    ie.intime, ie.outtime,
    ie.los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ie.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 83 AND 93
    AND ie.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code LIKE 'J45%' AND icd_version = 10
    )
),
control_cohort AS (
  SELECT 
    ie.subject_id, ie.hadm_id, ie.stay_id,
    ie.intime, ie.outtime,
    ie.los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ie.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 83 AND 93
    AND ie.hadm_id NOT IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code LIKE 'J45%' AND icd_version = 10
    )
),
sofa_calc AS (
  SELECT 
    coh.subject_id,
    coh.hadm_id,
    coh.stay_id,
    coh.cohort_type,
    MAX(sofa.sofa) as max_sofa_72h
  FROM (
    SELECT subject_id, hadm_id, stay_id, 'Asthma' as cohort_type FROM target_cohort
    UNION ALL
    SELECT subject_id, hadm_id, stay_id, 'Control' as cohort_type FROM control_cohort
  ) coh
  INNER JOIN `physionet-data.mimiciv_derived.sofa` sofa
    ON coh.stay_id = sofa.stay_id
  WHERE sofa.starttime BETWEEN 
    (SELECT intime FROM `physionet-data.mimiciv_icu.icustays` WHERE stay_id = coh.stay_id)
    AND DATETIME_ADD(
      (SELECT intime FROM `physionet-data.mimiciv_icu.icustays` WHERE stay_id = coh.stay_id), 
      INTERVAL 72 HOUR
    )
  GROUP BY coh.subject_id, coh.hadm_id, coh.stay_id, coh.cohort_type
)
SELECT 
  cohort_type,
  COUNT(*) AS n_patients,
  AVG(max_sofa_72h) AS avg_sofa_score,
  STDDEV(max_sofa_72h) AS std_sofa_score,
  APPROX_QUANTILES(max_sofa_72h, 100)[OFFSET(25)] AS p25_sofa,
  APPROX_QUANTILES(max_sofa_72h, 100)[OFFSET(50)] AS p50_sofa,
  APPROX_QUANTILES(max_sofa_72h, 100)[OFFSET(75)] AS p75_sofa,
  APPROX_QUANTILES(max_sofa_72h, 100)[OFFSET(95)] AS p95_sofa,
  AVG(coh.los) AS avg_los,
  SUM(coh.hospital_expire_flag) AS mortality_count,
  AVG(coh.hospital_expire_flag) AS mortality_rate
FROM (
  SELECT 
    tc.subject_id, tc.hadm_id, tc.stay_id,
    tc.los, tc.hospital_expire_flag,
    'Asthma' as cohort_type,
    sc.max_sofa_72h
  FROM target_cohort tc
  LEFT JOIN sofa_calc sc ON tc.stay_id = sc.stay_id AND sc.cohort_type = 'Asthma'
  
  UNION ALL
  
  SELECT 
    cc.subject_id, cc.hadm_id, cc.stay_id,
    cc.los, cc.hospital_expire_flag,
    'Control' as cohort_type,
    sc.max_sofa_72h
  FROM control_cohort cc
  LEFT JOIN sofa_calc sc ON cc.stay_id = sc.stay_id AND sc.cohort_type = 'Control'
) coh
GROUP BY cohort_type;