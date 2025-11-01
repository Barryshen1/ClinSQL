WITH hf_diagnoses AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND icd_code LIKE 'I50%'
),
icu_cohort AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id, 
    i.intime, 
    i.outtime,
    p.gender,
    EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  INNER JOIN hf_diagnoses d 
    ON i.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) BETWEEN 45 AND 55
),
vital_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE category = 'Vital Signs'
    AND label IN ('Heart Rate', 'MAP', 'Respiratory Rate')
),
vital_signs AS (
  SELECT 
    ce.subject_id, 
    ce.hadm_id, 
    ce.stay_id,
    ce.charttime,
    di.label,
    ce.valuenum,
    CASE 
      WHEN di.label = 'Heart Rate' AND ce.valuenum > 100 THEN 1
      WHEN di.label = 'MAP' AND ce.valuenum < 65 THEN 1
      WHEN di.label = 'Respiratory Rate' AND ce.valuenum > 20 THEN 1
      ELSE 0 
    END AS is_abnormal
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN vital_itemids vi 
    ON ce.itemid = vi.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.subject_id IN (SELECT subject_id FROM icu_cohort)
    AND ce.hadm_id IN (SELECT hadm_id FROM icu_cohort)
    AND ce.stay_id IN (SELECT stay_id FROM icu_cohort)
),
instability_scores AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    c.stay_id,
    SUM(vs.is_abnormal) AS instability_score
  FROM icu_cohort c
  LEFT JOIN vital_signs vs 
    ON c.subject_id = vs.subject_id 
    AND c.hadm_id = vs.hadm_id 
    AND c.stay_id = vs.stay_id
    AND vs.charttime BETWEEN c.intime AND c.intime + INTERVAL 72 HOUR
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
cohort_stats AS (
  SELECT 
    PERCENTILE_CONT(instability_score, 0.99) AS p99_instability_score,
    PERCENTILE_CONT(instability_score, 0.75) AS p75_instability_score
  FROM instability_scores
),
most_unstable AS (
  SELECT subject_id, hadm_id, stay_id, instability_score
  FROM instability_scores
  WHERE instability_score >= (SELECT p75_instability_score FROM cohort_stats)
),
stay_metrics AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    c.stay_id,
    c.intime,
    c.outtime,
    SUM(CASE WHEN vs.label = 'Heart Rate' THEN vs.is_abnormal ELSE 0 END) * 1.0 / 
      NULLIF(COUNT(CASE WHEN vs.label = 'Heart Rate' THEN 1 END), 0) AS prop_tachycardia,
    SUM(CASE WHEN vs.label = 'MAP' THEN vs.is_abnormal ELSE 0 END) * 1.0 / 
      NULLIF(COUNT(CASE WHEN vs.label = 'MAP' THEN 1 END), 0) AS prop_hypotension,
    SUM(CASE WHEN vs.label = 'Respiratory Rate' THEN vs.is_abnormal ELSE 0 END) * 1.0 / 
      NULLIF(COUNT(CASE WHEN vs.label = 'Respiratory Rate' THEN 1 END), 0) AS prop_tachypnea,
    TIMESTAMP_DIFF(c.outtime, c.intime, HOUR) AS los_hours,
    a.hospital_expire_flag AS died_in_hospital
  FROM icu_cohort c
  LEFT JOIN vital_signs vs 
    ON c.subject_id = vs.subject_id 
    AND c.hadm_id = vs.hadm_id 
    AND c.stay_id = vs.stay_id
    AND vs.charttime BETWEEN c.intime AND c.intime + INTERVAL 72 HOUR
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON c.subject_id = a.subject_id AND c.hadm_id = a.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.stay_id, c.intime, c.outtime, a.hospital_expire_flag
),
final_output AS (
  SELECT 
    (SELECT p99_instability_score FROM cohort_stats) AS p99_instability_score,
    'Most Unstable Quartile' AS cohort_group,
    AVG(prop_tachycardia) AS avg_prop_tachycardia,
    AVG(prop_hypotension) AS avg_prop_hypotension,
    AVG(prop_tachypnea) AS avg_prop_tachypnea,
    AVG(los_hours) AS avg_los_hours,
    AVG(CAST(died_in_hospital AS INT)) AS mortality_rate
  FROM stay_metrics
  WHERE stay_id IN (SELECT stay_id FROM most_unstable)

  UNION ALL

  SELECT 
    (SELECT p99_instability_score FROM cohort_stats),
    'Entire Cohort' AS cohort_group,
    AVG(prop_tachycardia),
    AVG(prop_hypotension),
    AVG(prop_tachypnea),
    AVG(los_hours),
    AVG(CAST(died_in_hospital AS INT))
  FROM stay_metrics
)
SELECT * FROM final_output;