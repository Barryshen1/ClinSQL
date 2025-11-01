WITH ich_patients AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%intracranial hemorrhage%'
     OR LOWER(d.long_title) LIKE '%intracerebral hemorrhage%'
     OR d.icd_code LIKE 'I61%'
     OR d.icd_code LIKE 'I62%'
),
cohort AS (
  SELECT p.subject_id, s.hadm_id, s.stay_id, s.intime, s.outtime, s.los,
         p.anchor_age + (EXTRACT(YEAR FROM s.intime) - p.anchor_year) AS age_at_admission,
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_icu`.icustays s ON p.subject_id = s.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON s.hadm_id = a.hadm_id
  JOIN ich_patients i ON s.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM s.intime) - p.anchor_year)) BETWEEN 47 AND 57
),
vital_signs AS (
  SELECT itemid, label, LOWER(category) AS category, lownormalvalue, highnormalvalue
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE linksto = 'chartevents'
    AND LOWER(category) IN ('vital signs', 'laboratory')
    AND LOWER(label) IN ('heart rate', 'mean blood pressure', 'respiratory rate', 'temperature', 'spo2')
),
abnormal_vitals AS (
  SELECT c.subject_id, c.stay_id,
         COUNT(*) AS instability_score
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON c.stay_id = ce.stay_id
  JOIN vital_signs vs
    ON ce.itemid = vs.itemid
  WHERE ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
    AND (
      ce.valuenum < vs.lownormalvalue OR
      ce.valuenum > vs.highnormalvalue
    )
  GROUP BY c.subject_id, c.stay_id
),
cohort_with_score AS (
  SELECT c.*, COALESCE(av.instability_score, 0) AS instability_score
  FROM cohort c
  LEFT JOIN abnormal_vitals av ON c.stay_id = av.stay_id
),
percentile_calc AS (
  SELECT
    instability_score,
    los,
    hospital_expire_flag,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS pct_rank
  FROM cohort_with_score
),
answer AS (
  SELECT
    SUM(CASE WHEN instability_score <= 75 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS percentile_rank_of_75,
    AVG(CASE WHEN pct_rank >= 0.9 THEN los END) AS avg_los_top_decile,
    AVG(CASE WHEN pct_rank >= 0.9 THEN hospital_expire_flag ELSE NULL END) AS mortality_rate_top_decile
  FROM percentile_calc
)
SELECT
  ROUND(percentile_rank_of_75, 4) AS percentile_rank_of_75,
  ROUND(avg_los_top_decile, 2) AS avg_los_top_decile,
  ROUND(mortality_rate_top_decile, 4) AS mortality_rate_top_decile
FROM answer;