WITH 
-- Define age range and gender
eligible_patients AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 44 AND 54
),

-- Identify stroke type (ischemic vs hemorrhagic)
stroke_patients AS (
  SELECT ep.subject_id, ep.hadm_id,
         CASE 
           WHEN di.icd_code IN ('433', '433.0', '433.1', '433.2', '433.8', '433.9') THEN 'ischemic'
           WHEN di.icd_code IN ('430', '431') THEN 'hemorrhagic'
           ELSE 'other'
         END AS stroke_type,
         ep.admittime, ep.dischtime, ep.hospital_expire_flag
  FROM eligible_patients ep
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON ep.hadm_id = di.hadm_id
  WHERE di.icd_code IN ('433', '433.0', '433.1', '433.2', '433.8', '433.9', '430', '431')
),

-- Calculate LOS and mortality
patient_outcomes AS (
  SELECT sp.subject_id, sp.hadm_id, sp.stroke_type,
         DATE_DIFF(sp.dischtime, sp.admittime, 'DAY') AS los_days,
         sp.hospital_expire_flag
  FROM stroke_patients sp
),

-- Comorbidity burden (simplified example, actual implementation may vary)
comorbidity_burden AS (
  SELECT subject_id, hadm_id,
         -- Simplified comorbidity calculation for demonstration
         COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY subject_id, hadm_id
),

-- ICU stays
icu_stays AS (
  SELECT po.subject_id, po.hadm_id,
         CASE 
           WHEN po.los_days <= 5 THEN '≤5'
           ELSE '>5'
         END AS los_category
  FROM patient_outcomes po
),

-- ICU interventions
interventions AS (
  SELECT icu.hadm_id,
         SUM(CASE WHEN i.itemid = 220050 AND ce.value = 'Yes' THEN 1 ELSE 0 END) / COUNT(DISTINCT icu.stay_id) AS mech_vent_rate,
         SUM(CASE WHEN i.itemid = 220179 AND ce.value = 'Yes' THEN 1 ELSE 0 END) / COUNT(DISTINCT icu.stay_id) AS vasopressors_rate,
         SUM(CASE WHEN i.itemid = 221927 AND ce.value = 'Yes' THEN 1 ELSE 0 END) / COUNT(DISTINCT icu.stay_id) AS rrt_rate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON icu.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` i ON ce.itemid = i.itemid
  GROUP BY icu.hadm_id
),

-- Comorbidity group
comorbidity_group AS (
  SELECT subject_id, hadm_id,
         CASE 
           WHEN comorbidity_count <= 2 THEN 'low'
           WHEN comorbidity_count BETWEEN 3 AND 5 THEN 'med'
           ELSE 'high'
         END AS comorbidity_group
  FROM comorbidity_burden
)

-- Final query
SELECT 
  sp.stroke_type,
  cg.comorbidity_group,
  icu.los_category,
  AVG(sp.hospital_expire_flag) AS mortality_rate,
  APPROX_QUANTILES(sp.los_days, 0.5)[OFFSET(1)] AS median_los,
  AVG(ii.mech_vent_rate) AS mech_vent_rate,
  AVG(ii.vasopressors_rate) AS vasopressors_rate,
  AVG(ii.rrt_rate) AS rrt_rate
FROM patient_outcomes sp
JOIN comorbidity_group cg ON sp.subject_id = cg.subject_id AND sp.hadm_id = cg.hadm_id
JOIN icu_stays icu ON sp.hadm_id = icu.hadm_id
LEFT JOIN interventions ii ON sp.hadm_id = ii.hadm_id
GROUP BY sp.stroke_type, cg.comorbidity_group, icu.los_category
ORDER BY sp.stroke_type, cg.comorbidity_group, icu.los_category;