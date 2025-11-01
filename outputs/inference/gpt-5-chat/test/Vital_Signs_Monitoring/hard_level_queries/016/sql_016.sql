WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    p.gender,
    p.anchor_age,
    icu.intime,
    icu.outtime,
    icu.los,
    a.hospital_expire_flag,
    -- Transplant flag: any diagnosis long_title contains 'transplant'
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
        WHERE di.hadm_id = icu.hadm_id
          AND LOWER(dd.long_title) LIKE '%transplant%'
      ) 
      THEN 'Transplant' 
      ELSE 'Non-Transplant' 
    END AS transplant_status
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
),

events AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    -- Count threshold events in first 72h
    SUM( CASE 
            WHEN LOWER(d.label) LIKE '%temperature%' 
                 AND ce.valuenum IS NOT NULL
                 AND d.unitname = '°C'
                 AND ce.valuenum > 38.5
            THEN 1 ELSE 0
         END ) AS fever_events,
    SUM( CASE 
            WHEN LOWER(d.label) LIKE '%spo2%' 
                 AND ce.valuenum IS NOT NULL
                 AND ce.valuenum < 90
            THEN 1 ELSE 0
         END ) AS low_spo2_events,
    SUM( CASE 
            WHEN LOWER(d.label) LIKE '%resp%' 
                 AND LOWER(d.label) LIKE '%rate%'
                 AND ce.valuenum IS NOT NULL
                 AND ce.valuenum > 20
            THEN 1 ELSE 0
         END ) AS high_rr_events
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON ce.itemid = d.itemid
  WHERE ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),

patient_scores AS (
  SELECT
    c.transplant_status,
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    e.fever_events + e.low_spo2_events + e.high_rr_events AS composite_score,
    c.los AS icu_los_days,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN events e
    ON c.subject_id = e.subject_id
    AND c.hadm_id = e.hadm_id
    AND c.stay_id = e.stay_id
)

SELECT
  transplant_status,
  -- median composite score
  APPROX_QUANTILES(composite_score, 100)[SAFE_OFFSET(50)] AS composite_score_median,
  APPROX_QUANTILES(composite_score, 100)[SAFE_OFFSET(25)] AS composite_score_p25,
  APPROX_QUANTILES(composite_score, 100)[SAFE_OFFSET(75)] AS composite_score_p75,
  -- median ICU LOS
  APPROX_QUANTILES(icu_los_days, 100)[SAFE_OFFSET(50)] AS icu_los_median_days,
  APPROX_QUANTILES(icu_los_days, 100)[SAFE_OFFSET(25)] AS icu_los_p25_days,
  APPROX_QUANTILES(icu_los_days, 100)[SAFE_OFFSET(75)] AS icu_los_p75_days,
  -- mortality rate
  COUNTIF(hospital_expire_flag = 1) / COUNT(*) AS mortality_rate
FROM patient_scores
GROUP BY transplant_status
ORDER BY transplant_status;