WITH pneumonia_hadms AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^48[0-6]'))
    OR 
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^J(09|1[0-8])'))
),
eligible_stays AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN pneumonia_hadms pn 
    ON i.hadm_id = pn.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 55 AND 65
),
scores AS (
  SELECT 
    es.stay_id,
    es.subject_id,
    es.hadm_id,
    es.intime,
    es.los,
    COUNT(le.labevent_id) AS instability_score
  FROM eligible_stays es
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.subject_id = es.subject_id
    AND le.hadm_id = es.hadm_id
    AND le.charttime >= es.intime
    AND le.charttime < TIMESTAMP_ADD(es.intime, INTERVAL 1 DAY)
  GROUP BY 
    es.stay_id, es.subject_id, es.hadm_id, es.intime, es.los
),
cohort_with_mort AS (
  SELECT 
    s.*,
    a.hospital_expire_flag
  FROM scores s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON s.hadm_id = a.hadm_id
),
percentile_calc AS (
  SELECT 
    COUNTIF(instability_score <= 60) * 100.0 / COUNT(*) AS score_percentile
  FROM cohort_with_mort
),
decile_stays AS (
  SELECT 
    los,
    hospital_expire_flag
  FROM (
    SELECT 
      los,
      hospital_expire_flag,
      NTILE(10) OVER (ORDER BY instability_score DESC) AS ntile_decile
    FROM cohort_with_mort
  )
  WHERE ntile_decile = 1
),
decile_stats AS (
  SELECT 
    AVG(los) AS avg_icu_los,
    COUNTIF(hospital_expire_flag = 1) * 100.0 / COUNT(*) AS mortality_pct
  FROM decile_stays
)
SELECT 
  pc.score_percentile,
  ds.avg_icu_los,
  ds.mortality_pct
FROM percentile_calc pc
CROSS JOIN decile_stats ds;