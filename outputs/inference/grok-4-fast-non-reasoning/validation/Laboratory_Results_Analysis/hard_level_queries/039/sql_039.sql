WITH pneumonia_cohort AS (
  -- Primary pneumonia admissions for males 60-70
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND CAST(a.hadm_id AS INT64) = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND d.seq_num = 1
    AND (d.icd_code LIKE 'J18%' OR d.icd_code LIKE 'J15%')
    AND d.icd_version = 'ICD-10-CM'
    AND a.dischtime IS NOT NULL
),

all_inpatients AS (
  -- All male inpatients aged 18+
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age >= 18
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND a.dischtime IS NOT NULL
),

lab_instability_scores AS (
  -- 72-hour lab instability score (count of deranged labs)
  SELECT 
    pc.hadm_id,
    COUNT(DISTINCT le.itemid) AS instability_score
  FROM pneumonia_cohort pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON pc.subject_id = le.subject_id 
    AND CAST(pc.hadm_id AS INT64) = le.hadm_id
    AND le.charttime >= pc.admittime 
    AND le.charttime <= TIMESTAMP_ADD(pc.admittime, INTERVAL 72 HOUR)
  WHERE le.itemid IN (
    654, 669,  -- WBC
    706, 831,  -- Sodium
    718, 829,  -- Potassium
    792, 791,  -- Creatinine
    747,       -- Lactate (arterial/venous combined)
    1975       -- Bilirubin total
  )
    AND le.valuenum IS NOT NULL
    AND (
      (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
      OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
      OR (le.itemid = 747 AND le.valuenum > 2.0)  -- Lactate threshold if no ref
    )
  GROUP BY pc.hadm_id
),

critical_events_cohort AS (
  -- Critical events for pneumonia cohort (distinct types per admission)
  SELECT 
    pc.hadm_id,
    (CASE WHEN ventilation.present = 1 THEN 1 ELSE 0 END +
     CASE WHEN vasopressor.present = 1 THEN 1 ELSE 0 END +
     CASE WHEN arrest.present = 1 THEN 1 ELSE 0 END +
     CASE WHEN pc.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS critical_freq
  FROM pneumonia_cohort pc
  LEFT JOIN (
    SELECT hadm_id, 1 AS present
    FROM pneumonia_cohort pc2
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON pc2.subject_id = icu.subject_id AND pc2.hadm_id = icu.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON icu.stay_id = pe.stay_id
    WHERE pe.itemid IN (225477, 225468)
    GROUP BY hadm_id
  ) ventilation ON pc.hadm_id = ventilation.hadm_id
  LEFT JOIN (
    SELECT hadm_id, 1 AS present
    FROM pneumonia_cohort pc2
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON pc2.subject_id = icu.subject_id AND pc2.hadm_id = icu.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
      ON icu.stay_id = ie.stay_id
    WHERE ie.itemid IN (220615, 30047, 30120)
    GROUP BY hadm_id
  ) vasopressor ON pc.hadm_id = vasopressor.hadm_id
  LEFT JOIN (
    SELECT CAST(d.hadm_id AS INT64) AS hadm_id, 1 AS present
    FROM pneumonia_cohort pc2
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON pc2.subject_id = d.subject_id AND CAST(pc2.hadm_id AS INT64) = d.hadm_id
    WHERE d.icd_code LIKE 'I46%'
    GROUP BY hadm_id
  ) arrest ON pc.hadm_id = arrest.hadm_id
),

critical_events_all AS (
  -- Same for all inpatients
  SELECT 
    ai.hadm_id,
    (CASE WHEN ventilation.present = 1 THEN 1 ELSE 0 END +
     CASE WHEN vasopressor.present = 1 THEN 1 ELSE 0 END +
     CASE WHEN arrest.present = 1 THEN 1 ELSE 0 END +
     CASE WHEN ai.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS critical_freq
  FROM all_inpatients ai
  LEFT JOIN (
    SELECT ai2.hadm_id, 1 AS present
    FROM all_inpatients ai2
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON ai2.subject_id = icu.subject_id AND ai2.hadm_id = icu.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON icu.stay_id = pe.stay_id
    WHERE pe.itemid IN (225477, 225468)
    GROUP BY ai2.hadm_id
  ) ventilation ON ai.hadm_id = ventilation.hadm_id
  LEFT JOIN (
    SELECT ai2.hadm_id, 1 AS present
    FROM all_inpatients ai2
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON ai2.subject_id = icu.subject_id AND ai2.hadm_id = icu.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
      ON icu.stay_id = ie.stay_id
    WHERE ie.itemid IN (220615, 30047, 30120)
    GROUP BY ai2.hadm_id
  ) vasopressor ON ai.hadm_id = vasopressor.hadm_id
  LEFT JOIN (
    SELECT CAST(d.hadm_id AS INT64) AS hadm_id, 1 AS present
    FROM all_inpatients ai2
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON ai2.subject_id = d.subject_id AND CAST(ai2.hadm_id AS INT64) = d.hadm_id
    WHERE d.icd_code LIKE 'I46%'
    GROUP BY hadm_id
  ) arrest ON ai.hadm_id = arrest.hadm_id
)

-- Final metrics
SELECT 
  -- 75th percentile instability score
  PERCENTILE_CONT(0.75 IGNORE NULLS) OVER() AS p75_lab_instability_score,
  
  -- Mean critical event frequency
  AVG(COALESCE(cec.critical_freq, 0)) AS mean_critical_freq_cohort,
  (SELECT AVG(COALESCE(cea.critical_freq, 0)) FROM critical_events_all cea) AS mean_critical_freq_all,
  
  -- Cohort LOS and mortality
  AVG(TIMESTAMPDIFF(DAY, pc.admittime, pc.dischtime)) AS mean_los_days,
  AVG(pc.hospital_expire_flag) AS mortality_rate
FROM pneumonia_cohort pc
LEFT JOIN lab_instability_scores lis ON pc.hadm_id = lis.hadm_id
LEFT JOIN critical_events_cohort cec ON pc.hadm_id = cec.hadm_id;