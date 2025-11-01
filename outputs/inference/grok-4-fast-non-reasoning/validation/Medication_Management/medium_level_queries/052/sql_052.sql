WITH cohort AS (
  -- Base cohort: 45-55 yo males with >=48h ICU stay, inpatient survivors
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND a.hospital_expire_flag = 0
    AND i.los >= 2
),

diabetes AS (
  -- Admissions with T2DM (E11.*)
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.icd_version = '10'
    AND di.icd_code LIKE 'E11%'
),

hf AS (
  -- Admissions with heart failure (I50.*)
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.icd_version = '10'
    AND di.icd_code LIKE 'I50%'
),

qualified_admissions AS (
  -- Combine: cohort + T2DM + HF
  SELECT c.*
  FROM cohort c
  INNER JOIN diabetes d ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
  INNER JOIN hf h ON c.subject_id = h.subject_id AND c.hadm_id = h.hadm_id
),

med_events AS (
  -- Medication events in qualified stays, filtered by time windows
  SELECT 
    qa.hadm_id,
    ie.itemid,
    CASE 
      WHEN TIMESTAMP_DIFF(ie.starttime, qa.intime, HOUR) < 48 
           AND ie.starttime >= qa.intime 
      THEN 'first_48h'
      WHEN TIMESTAMP_DIFF(ie.starttime, qa.outtime, HOUR) >= -24 
           AND ie.starttime < qa.outtime 
      THEN 'final_24h'
    END AS time_window
  FROM qualified_admissions qa
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON qa.subject_id = ie.subject_id 
    AND qa.hadm_id = ie.hadm_id 
    AND CAST(qa.stay_id AS STRING) = ie.stay_id
  WHERE ie.amount > 0
    AND (ie.itemid IN (225798, 225828, 225831, 225910, 50006)  -- Insulin
         OR ie.itemid IN (50001, 50002, 50003, 50004, 50005, 50007, 50008, 50009, 50010, 
                          50011, 50012, 50013, 50014, 50015))  -- Oral antidiabetics
    AND (TIMESTAMP_DIFF(ie.starttime, qa.intime, HOUR) < 48 AND ie.starttime >= qa.intime
         OR TIMESTAMP_DIFF(ie.starttime, qa.outtime, HOUR) >= -24 AND ie.starttime < qa.outtime)
)

-- Final percentages: % of admissions with insulin vs oral per window
SELECT 
  time_window,
  ROUND(SUM(CASE WHEN insulin_received = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT hadm_id), 1) AS pct_insulin,
  ROUND(SUM(CASE WHEN oral_received = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT hadm_id), 1) AS pct_oral
FROM (
  SELECT 
    m.hadm_id,
    m.time_window,
    MAX(CASE WHEN m.itemid IN (225798, 225828, 225831, 225910, 50006) THEN 1 ELSE 0 END) AS insulin_received,
    MAX(CASE WHEN m.itemid IN (50001, 50002, 50003, 50004, 50005, 50007, 50008, 50009, 50010, 
                               50011, 50012, 50013, 50014, 50015) THEN 1 ELSE 0 END) AS oral_received
  FROM med_events m
  GROUP BY m.hadm_id, m.time_window
) pivoted
GROUP BY time_window
ORDER BY 
  CASE time_window 
    WHEN 'first_48h' THEN 1 
    WHEN 'final_24h' THEN 2 
  END;