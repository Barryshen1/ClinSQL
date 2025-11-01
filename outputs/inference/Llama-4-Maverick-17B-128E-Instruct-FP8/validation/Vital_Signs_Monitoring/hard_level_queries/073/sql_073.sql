WITH ich_patients AS (
  SELECT DISTINCT h.subject_id, h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON h.icd_code = d.icd_code AND h.icd_version = d.icd_version
  WHERE d.long_title LIKE '%Intracranial hemorrhage%' 
  OR d.long_title LIKE '%ICH%'
),
icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
),
patient_info AS (
  SELECT p.subject_id, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 47 AND 57
),
vital_signs AS (
  SELECT c.stay_id, c.charttime, c.itemid, c.valuenum,
         d.label,
         ROW_NUMBER() OVER (PARTITION BY c.stay_id, d.label ORDER BY c.charttime) as rn
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  INNER JOIN icu_stays i ON c.stay_id = i.stay_id
  WHERE d.label IN ('Heart Rate', 'Systolic Blood Pressure')
  AND c.charttime <= TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
),
instability_score AS (
  SELECT stay_id, COUNT(*) as score
  FROM vital_signs
  WHERE (label = 'Heart Rate' AND valuenum > 100)
  OR (label = 'Systolic Blood Pressure' AND (valuenum > 180 OR valuenum < 90))
  GROUP BY stay_id
),
combined_data AS (
  SELECT i.stay_id, i.intime, i.outtime, ip.anchor_age,
         COALESCE(s.score, 0) as instability_score,
         CASE WHEN p.dod IS NOT NULL THEN 1 ELSE 0 END as mortality
  FROM icu_stays i
  INNER JOIN patient_info ip ON i.subject_id = ip.subject_id
  LEFT JOIN instability_score s ON i.stay_id = s.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE i.hadm_id IN (SELECT hadm_id FROM ich_patients)
),
percentile_calc AS (
  SELECT instability_score, 
         PERCENT_RANK() OVER (ORDER BY instability_score) as percentile
  FROM combined_data
),
top_decile AS (
  SELECT *
  FROM combined_data
  WHERE instability_score >= (SELECT instability_score FROM percentile_calc WHERE percentile >= 0.9)
)
SELECT 
  (SELECT percentile FROM percentile_calc WHERE instability_score = 75) as percentile_of_score_75,
  AVG(TIMESTAMP_DIFF(outtime, intime, HOUR)) as avg_icu_los_hours,
  AVG(mortality) as avg_mortality
FROM top_decile;