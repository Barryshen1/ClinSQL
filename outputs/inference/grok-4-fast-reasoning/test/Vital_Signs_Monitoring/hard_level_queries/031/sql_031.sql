WITH surgical_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE admission_type = 'SURGICAL'
),
icu_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
postop_icu_hadms AS (
  SELECT s.hadm_id
  FROM surgical_hadms s
  INNER JOIN icu_hadms i ON s.hadm_id = i.hadm_id
),
los_per_hadm AS (
  SELECT hadm_id, SUM(los) AS icu_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE hadm_id IN (SELECT hadm_id FROM postop_icu_hadms)
  GROUP BY hadm_id
),
all_adverse_events AS (
  SELECT 
    ce.hadm_id,
    COUNTIF(ce.itemid IN (676, 677, 678) AND ce.valuenum > 38.5) AS fever_events,
    COUNTIF(ce.itemid = 220277 AND ce.valuenum < 90) AS hypoxia_events,
    COUNTIF(ce.itemid IN (618, 220210) AND ce.valuenum > 20) AS tachypnea_events
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN postop_icu_hadms pi ON ce.hadm_id = pi.hadm_id
  WHERE ce.itemid IN (676, 677, 678, 220277, 618, 220210)
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.hadm_id
),
all_patients_data AS (
  SELECT p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN postop_icu_hadms pi ON a.hadm_id = pi.hadm_id
  WHERE p.anchor_age > 18
),
all_cohort_with_metrics AS (
  SELECT 
    apd.*,
    COALESCE(ae.fever_events, 0) > 0 AS had_fever,
    COALESCE(ae.hypoxia_events, 0) > 0 AS had_hypoxia,
    COALESCE(ae.tachypnea_events, 0) AS tachypnea_events,
    COALESCE(l.icu_los, 0) AS icu_los,
    (COALESCE(ae.fever_events, 0) + COALESCE(ae.hypoxia_events, 0) + COALESCE(ae.tachypnea_events, 0)) AS instability_score
  FROM all_patients_data apd
  LEFT JOIN all_adverse_events ae ON apd.hadm_id = ae.hadm_id
  LEFT JOIN los_per_hadm l ON apd.hadm_id = l.hadm_id
),
specific_cohort AS (
  SELECT *
  FROM all_cohort_with_metrics
  WHERE gender = 'M' AND anchor_age BETWEEN 63 AND 73
),
q75 AS (
  SELECT APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS q75_score
  FROM specific_cohort
),
top_quartile AS (
  SELECT sc.*
  FROM specific_cohort sc
  CROSS JOIN q75 q
  WHERE sc.instability_score >= q.q75_score
),
p95_val AS (
  SELECT APPROX_QUANTILES(instability_score, 20)[OFFSET(19)] AS p95_instability
  FROM top_quartile
),
comparison AS (
  SELECT 'top_quartile' AS patient_group,
         AVG(CAST(had_fever AS INT64)) AS fever_rate,
         AVG(CAST(had_hypoxia AS INT64)) AS spo2_low_rate,
         AVG(tachypnea_events) AS mean_rr_episodes,
         AVG(icu_los) AS mean_icu_los,
         AVG(CAST(hospital_expire_flag AS INT64)) AS mortality_rate
  FROM top_quartile
  UNION ALL
  SELECT 'baseline_cohort' AS patient_group,
         AVG(CAST(had_fever AS INT64)) AS fever_rate,
         AVG(CAST(had_hypoxia AS INT64)) AS spo2_low_rate,
         AVG(tachypnea_events) AS mean_rr_episodes,
         AVG(icu_los) AS mean_icu_los,
         AVG(CAST(hospital_expire_flag AS INT64)) AS mortality_rate
  FROM specific_cohort
)
SELECT 
  c.*,
  p.p95_instability
FROM comparison c
CROSS JOIN p95_val p
ORDER BY patient_group;