WITH eligible_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 47 AND 57
    AND (LOWER(did.long_title) LIKE '%intracranial hemorrhage%'
         OR LOWER(did.long_title) LIKE '%subarachnoid hemorrhage%'
         OR LOWER(did.long_title) LIKE '%intracerebral hemorrhage%')
),

vital_signs AS (
  SELECT
    ep.subject_id,
    ep.stay_id,
    ce.charttime,
    ce.itemid,
    ce.valuenum,
    di.label
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ep.stay_id = ce.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE ce.charttime >= ep.intime
    AND ce.charttime <= TIMESTAMP_ADD(ep.intime, INTERVAL 72 HOUR)
    AND di.label IN (
      'Heart Rate',
      'Systolic BP',
      'Diastolic BP',
      'Mean BP',
      'Respiratory Rate',
      'Temperature',
      'SpO2'
    )
    AND ce.valuenum IS NOT NULL
),

abnormal_vitals AS (
  SELECT
    subject_id,
    stay_id,
    COUNT(*) AS instability_score
  FROM vital_signs
  WHERE (
    (label = 'Heart Rate' AND (valuenum < 40 OR valuenum > 120))
    OR (label = 'Systolic BP' AND (valuenum < 90 OR valuenum > 180))
    OR (label = 'Diastolic BP' AND (valuenum < 50 OR valuenum > 110))
    OR (label = 'Mean BP' AND (valuenum < 60 OR valuenum > 130))
    OR (label = 'Respiratory Rate' AND (valuenum < 8 OR valuenum > 30))
    OR (label = 'Temperature' AND (valuenum < 35 OR valuenum > 39))
    OR (label = 'SpO2' AND valuenum < 90)
  )
  GROUP BY subject_id, stay_id
),

all_scores AS (
  SELECT
    ep.subject_id,
    ep.stay_id,
    ep.los,
    ep.hospital_expire_flag,
    COALESCE(av.instability_score, 0) AS instability_score
  FROM eligible_patients ep
  LEFT JOIN abnormal_vitals av ON ep.stay_id = av.stay_id
),

p90_threshold AS (
  SELECT PERCENTILE_CONT(instability_score, 0.9) AS p90_threshold
  FROM all_scores
),

top_decile AS (
  SELECT
    AVG(los) AS avg_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM all_scores
  WHERE instability_score >= (SELECT p90_threshold FROM p90_threshold)
)

SELECT
  (SELECT SUM(CASE WHEN instability_score <= 75 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) FROM all_scores) AS percentile_of_75,
  td.avg_icu_los,
  td.mortality_rate
FROM top_decile td
LIMIT 1;