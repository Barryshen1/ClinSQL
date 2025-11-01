WITH patients_cohort AS (
  SELECT p.subject_id, p.anchor_age, ie.hadm_id, ie.stay_id, ie.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 45 AND 55
),
arf_patients AS (
  SELECT DISTINCT le.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON le.itemid = di.itemid
  WHERE di.label = 'Creatinine' AND le.valuenum > 2
),
vital_signs AS (
  SELECT ce.subject_id, ce.stay_id, ce.charttime, ce.itemid, ce.valuenum, di.label
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  JOIN patients_cohort pc ON ce.subject_id = pc.subject_id AND ce.stay_id = pc.stay_id
  WHERE di.label IN ('Heart Rate', 'Mean Arterial Pressure') AND ce.charttime <= TIMESTAMP_ADD(pc.intime, INTERVAL 48 HOUR)
),
instability_score AS (
  SELECT vs.subject_id, vs.stay_id,
         SUM(CASE WHEN vs.label = 'Heart Rate' AND vs.valuenum > 100 THEN 1 ELSE 0 END) +
         SUM(CASE WHEN vs.label = 'Mean Arterial Pressure' AND vs.valuenum < 65 THEN 1 ELSE 0 END) AS score
  FROM vital_signs vs
  GROUP BY vs.subject_id, vs.stay_id
),
percentile_95 AS (
  SELECT APPROX_QUANTILES(score, 100)[OFFSET(95)] AS threshold
  FROM instability_score
),
top_quartile AS (
  SELECT subject_id, stay_id
  FROM instability_score
  WHERE score >= (SELECT threshold FROM percentile_95)
)
SELECT 
  AVG(CASE WHEN vs.valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_rate,
  AVG(CASE WHEN vs.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_rate,
  AVG(TIMESTAMP_DIFF(ie.outtime, ie.intime, HOUR)) AS icu_los,
  AVG(CASE WHEN p.dod IS NOT NULL AND TIMESTAMP_DIFF(p.dod, ie.intime, HOUR) <= TIMESTAMP_DIFF(ie.outtime, ie.intime, HOUR) THEN 1 ELSE 0 END) AS mortality_rate
FROM top_quartile tq
JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON tq.stay_id = ie.stay_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON ie.subject_id = p.subject_id
LEFT JOIN vital_signs vs ON tq.stay_id = vs.stay_id;