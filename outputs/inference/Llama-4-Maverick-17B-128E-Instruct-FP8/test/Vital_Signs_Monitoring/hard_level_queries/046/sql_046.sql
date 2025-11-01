WITH ischemic_stroke_patients AS (
  SELECT DISTINCT h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON h.icd_code = d.icd_code AND h.icd_version = d.icd_version
  WHERE d.long_title LIKE '%Ischemic stroke%' AND h.icd_version = 10
),
eligible_patients AS (
  SELECT p.subject_id, p.anchor_age, icu.hadm_id, icu.stay_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.subject_id = icu.subject_id
  JOIN ischemic_stroke_patients isp ON icu.hadm_id = isp.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 84 AND 94
),
vital_signs AS (
  SELECT ep.stay_id, ce.charttime, di.label, ce.valuenum
  FROM eligible_patients ep
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ep.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE ce.charttime BETWEEN ep.intime AND TIMESTAMP_ADD(ep.intime, INTERVAL 72 HOUR)
  AND di.label IN ('Heart Rate', 'Systolic Blood Pressure', 'Diastolic Blood Pressure', 'Respiratory Rate', 'Oxygen Saturation')
),
instability_scores AS (
  SELECT stay_id, 
         SUM(CASE WHEN label = 'Heart Rate' AND (valuenum < 40 OR valuenum > 130) THEN 1 ELSE 0 END) +
         SUM(CASE WHEN label = 'Systolic Blood Pressure' AND (valuenum < 90 OR valuenum > 180) THEN 1 ELSE 0 END) +
         SUM(CASE WHEN label = 'Diastolic Blood Pressure' AND (valuenum < 60 OR valuenum > 120) THEN 1 ELSE 0 END) +
         SUM(CASE WHEN label = 'Respiratory Rate' AND (valuenum < 8 OR valuenum > 30) THEN 1 ELSE 0 END) +
         SUM(CASE WHEN label = 'Oxygen Saturation' AND valuenum < 90 THEN 1 ELSE 0 END) AS score
  FROM vital_signs
  GROUP BY stay_id
),
icu_outcomes AS (
  SELECT icu.stay_id, icu.los, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON icu.hadm_id = adm.hadm_id
),
percentile_and_outcomes AS (
  SELECT 
    PERCENT_RANK() OVER (ORDER BY isc.score) AS percentile,
    isc.score,
    icu.los,
    icu.hospital_expire_flag AS mortality
  FROM instability_scores isc
  JOIN icu_outcomes icu ON isc.stay_id = icu.stay_id
)
SELECT 
  percentile,
  score,
  los,
  mortality
FROM percentile_and_outcomes
WHERE score = 80 OR percentile >= 0.75;