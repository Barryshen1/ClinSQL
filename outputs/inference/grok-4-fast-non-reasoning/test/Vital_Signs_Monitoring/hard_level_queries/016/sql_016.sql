WITH first_icu_stays AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    ic.stay_id,
    ic.hadm_id,
    ic.intime,
    ic.outtime,
    ic.los,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY ic.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ic.subject_id = p.subject_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 57 AND 67
),
eligible_stays AS (
  SELECT 
    fis.*,
    a.hospital_expire_flag,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON di.icd_code = dd.icd_code 
          AND di.icd_version = dd.icd_version
        WHERE di.subject_id = fis.subject_id 
          AND di.hadm_id = fis.hadm_id
          AND (
            (di.icd_version = 'ICD-9' AND REGEXP_CONTAINS(di.icd_code, r'^V42|^996'))
            OR (di.icd_version = 'ICD-10' AND REGEXP_CONTAINS(di.icd_code, r'^Z94|^T86'))
          )
      ) THEN 1 ELSE 0 
    END AS is_transplant
  FROM first_icu_stays fis
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON fis.hadm_id = a.hadm_id
  WHERE fis.rn = 1
),
fever_events AS (
  SELECT 
    subject_id, hadm_id, stay_id, 
    COUNT(DISTINCT charttime) AS fever_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN eligible_stays es ON ce.subject_id = es.subject_id 
    AND CAST(ce.hadm_id AS INT64) = es.hadm_id 
    AND ce.stay_id = es.stay_id
  WHERE ce.itemid IN (676, 677)  -- Oral/Auxillary temp °C
    AND ce.valuenum > 38.5
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= es.intime
    AND ce.charttime <= DATETIME_ADD(es.intime, INTERVAL 3 DAY)
  GROUP BY subject_id, hadm_id, stay_id
),
spo2_events AS (
  SELECT 
    subject_id, hadm_id, stay_id, 
    COUNT(DISTINCT charttime) AS spo2_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN eligible_stays es ON ce.subject_id = es.subject_id 
    AND CAST(ce.hadm_id AS INT64) = es.hadm_id 
    AND ce.stay_id = es.stay_id
  WHERE ce.itemid IN (220277, 220339, 223762)  -- SpO2
    AND ce.valuenum < 90
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= es.intime
    AND ce.charttime <= DATETIME_ADD(es.intime, INTERVAL 3 DAY)
  GROUP BY subject_id, hadm_id, stay_id
),
rr_events AS (
  SELECT 
    subject_id, hadm_id, stay_id, 
    COUNT(DISTINCT charttime) AS rr_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN eligible_stays es ON ce.subject_id = es.subject_id 
    AND CAST(ce.hadm_id AS INT64) = es.hadm_id 
    AND ce.stay_id = es.stay_id
  WHERE ce.itemid IN (618, 619, 220210)  -- Resp rate
    AND ce.valuenum > 20
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= es.intime
    AND ce.charttime <= DATETIME_ADD(es.intime, INTERVAL 3 DAY)
  GROUP BY subject_id, hadm_id, stay_id
),
instability_scores AS (
  SELECT 
    es.subject_id,
    es.stay_id,
    es.is_transplant,
    COALESCE(f.fever_count, 0) + COALESCE(s.spo2_count, 0) + COALESCE(r.rr_count, 0) AS instability_score,
    es.los,
    CASE WHEN es.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END AS mortality
  FROM eligible_stays es
  LEFT JOIN fever_events f ON es.subject_id = f.subject_id AND es.stay_id = f.stay_id
  LEFT JOIN spo2_events s ON es.subject_id = s.subject_id AND es.stay_id = s.stay_id
  LEFT JOIN rr_events r ON es.subject_id = r.subject_id AND es.stay_id = r.stay_id
)
SELECT 
  is_transplant,
  -- Instability score percentiles
  PERCENTILE_CONT(0.5) OVER (PARTITION BY is_transplant) AS median_instability_score,
  PERCENTILE_CONT(0.25) OVER (PARTITION BY is_transplant) AS p25_instability_score,
  PERCENTILE_CONT(0.75) OVER (PARTITION BY is_transplant) AS p75_instability_score,
  -- LOS percentiles
  PERCENTILE_CONT(0.5) OVER (PARTITION BY is_transplant) AS median_los,
  PERCENTILE_CONT(0.25) OVER (PARTITION BY is_transplant) AS p25_los,
  PERCENTILE_CONT(0.75) OVER (PARTITION BY is_transplant) AS p75_los,
  -- Mortality rate
  AVG(mortality) OVER (PARTITION BY is_transplant) AS mortality_rate,
  COUNT(*) OVER (PARTITION BY is_transplant) AS n_patients
FROM instability_scores
ORDER BY is_transplant;