WITH asthma_codes AS (
  -- ICD codes for asthma
  SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code LIKE '493.%')
     OR (icd_version = 10 AND icd_code LIKE 'J45.%')
     OR (icd_code = 'J46')
),
eligible_stays AS (
  -- First ICU stay per admission for females aged 83-93
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los,
    pat.gender,
    pat.anchor_age,
    CASE WHEN ac.icd_code IS NOT NULL THEN 1 ELSE 0 END AS asthma_cohort
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON icu.subject_id = diag.subject_id 
    AND icu.hadm_id = diag.hadm_id
    AND diag.seq_num <= 10  -- Focus on primary/secondary
  LEFT JOIN asthma_codes ac 
    ON diag.icd_code = ac.icd_code
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 83 AND 93
    AND icu.los > 0
  QUALIFY ROW_NUMBER() OVER (PARTITION BY icu.hadm_id ORDER BY icu.intime) = 1
),
mortality AS (
  -- In-hospital mortality flag (extend to post-discharge if dod > dischtime)
  SELECT 
    es.*,
    CASE 
      WHEN adm.hospital_expire_flag = 1 
        OR (pat.dod IS NOT NULL AND pat.dod > adm.dischtime) 
      THEN 1 ELSE 0 
    END AS mortality
  FROM eligible_stays es
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON es.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON es.subject_id = pat.subject_id
),
resp_events AS (
  -- Respiratory events in first 72h
  SELECT 
    mort.subject_id,
    mort.hadm_id,
    mort.stay_id,
    mort.intime,
    mort.asthma_cohort,
    mort.los,
    mort.mortality,
    ce.charttime,
    ce.itemid,
    ce.valuenum
  FROM mortality mort
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON mort.subject_id = ce.subject_id
    AND mort.stay_id = ce.stay_id
  WHERE (ce.itemid IN (618, 220045)  -- RR
     OR ce.itemid = 220277)  -- SpO2
    AND ce.charttime BETWEEN mort.intime AND TIMESTAMP_ADD(mort.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
    AND (
      (ce.itemid IN (618, 220045) AND ce.valuenum BETWEEN 5 AND 60) OR
      (ce.itemid = 220277 AND ce.valuenum BETWEEN 50 AND 100)
    )
),
patient_vitals AS (
  -- Aggregates per patient in first 72h for instability score
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    asthma_cohort,
    los,
    mortality,
    -- RR stats
    AVG(CASE WHEN itemid IN (618, 220045) THEN valuenum END) AS rr_mean,
    STDDEV(CASE WHEN itemid IN (618, 220045) THEN valuenum END) AS rr_std,
    COUNT(CASE WHEN itemid IN (618, 220045) THEN 1 END) AS rr_count,
    -- SpO2 stats
    AVG(CASE WHEN itemid = 220277 THEN valuenum END) AS spo2_mean,
    STDDEV(CASE WHEN itemid = 220277 THEN valuenum END) AS spo2_std,
    COUNT(CASE WHEN itemid = 220277 THEN 1 END) AS spo2_count
  FROM resp_events
  GROUP BY subject_id, hadm_id, stay_id, asthma_cohort, los, mortality
  HAVING rr_count > 0 OR spo2_count > 0  -- At least some vitals
),
instability_scores AS (
  -- Instability score: max CV (coefficient of variation) for RR or SpO2
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    asthma_cohort,
    los,
    mortality,
    GREATEST(
      SAFE_DIVIDE(rr_std, rr_mean),
      SAFE_DIVIDE(spo2_std, spo2_mean)
    ) AS instability_score
  FROM patient_vitals
),
cohort_summary AS (
  SELECT 
    asthma_cohort,
    COUNT(*) AS n_patients,
    COUNT(instability_score) AS n_with_score,
    AVG(instability_score) AS mean_score,
    STDDEV(instability_score) AS sd_score,
    PERCENTILE_CONT(instability_score, 0.25) AS p25_score,
    PERCENTILE_CONT(instability_score, 0.50) AS p50_score,
    PERCENTILE_CONT(instability_score, 0.75) AS p75_score,
    PERCENTILE_CONT(instability_score, 0.95) AS p95_score,
    AVG(los) AS mean_los,
    AVG(mortality) AS mortality_rate
  FROM instability_scores
  GROUP BY asthma_cohort
)
SELECT 
  CASE WHEN asthma_cohort = 1 THEN 'Asthma Cohort' ELSE 'Age-Matched Cohort' END AS cohort,
  n_patients,
  n_with_score,
  ROUND(mean_score, 4) AS mean_instability_score,
  ROUND(sd_score, 4) AS sd_instability_score,
  ROUND(p25_score, 4) AS p25_score,
  ROUND(p50_score, 4) AS p50_score,
  ROUND(p75_score, 4) AS p75_score,
  ROUND(p95_score, 4) AS p95_score,
  ROUND(mean_los, 2) AS mean_icu_los_days,
  ROUND(mortality_rate * 100, 2) AS mortality_rate_percent
FROM cohort_summary
ORDER BY asthma_cohort DESC;