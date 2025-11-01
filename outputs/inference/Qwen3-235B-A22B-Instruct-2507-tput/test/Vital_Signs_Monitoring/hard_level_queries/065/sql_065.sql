with RRT, what is the 90th percentile of the 48-hour composite vital instability score?
For the top decile, compare hypotension (MAP<65), tachycardia episodes, ICU LOS, and mortality vs males 70–80 without RRT.
*/

WITH patients_age AS (
  SELECT
    p.subject_id,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) AS age_at_admission,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los AS icu_los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 70 AND 80
),

-- Identify RRT procedures within first 48 hours of ICU stay
rrt_flag AS (
  SELECT DISTINCT
    pe.subject_id,
    pe.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu`.procedureevents pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON pe.itemid = di.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON pe.stay_id = i.stay_id
  WHERE (LOWER(di.label) LIKE '%dialysis%'
         OR LOWER(di.label) LIKE '%crrt%'
         OR LOWER(di.label) LIKE '%continuous renal replacement%'
         OR LOWER(di.label) LIKE '%hemodialysis%')
    AND pe.starttime >= i.intime
    AND pe.starttime <= DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
),

-- Extract vital signs within first 48 hours of ICU stay
vitals_48h AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    di.label,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN patients_age pa
    ON ce.subject_id = pa.subject_id AND ce.hadm_id = pa.hadm_id
  WHERE ce.charttime >= pa.intime
    AND ce.charttime <= DATETIME_ADD(pa.intime, INTERVAL 48 HOUR)
    AND di.label IN ('Heart Rate', 'NIBP Mean', 'Arterial BP Mean', 'SpO2', 'Respiratory Rate', 'Temperature')
),

-- Count abnormal vital signs per patient
abnormal_vitals AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(CASE
      WHEN label IN ('NIBP Mean', 'Arterial BP Mean') AND valuenum < 65 THEN 1
      ELSE 0
    END) AS hypotension_count,
    SUM(CASE
      WHEN label = 'Heart Rate' AND valuenum > 100 THEN 1
      ELSE 0
    END) AS tachycardia_count,
    SUM(CASE
      WHEN label = 'SpO2' AND valuenum < 90 THEN 1
      ELSE 0
    END) AS hypoxemia_count,
    SUM(CASE
      WHEN label = 'Respiratory Rate' AND (valuenum < 8 OR valuenum > 25) THEN 1
      ELSE 0
    END) AS abnormal_rr_count,
    SUM(CASE
      WHEN label = 'Temperature' AND (valuenum < 35 OR valuenum > 37.5) THEN 1
      ELSE 0
    END) AS abnormal_temp_count
  FROM vitals_48h
  GROUP BY subject_id, hadm_id
),

-- Combine with patient data and compute composite score
patient_scores AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.icu_los,
    pa.hospital_expire_flag,
    COALESCE(rv.hypotension_count, 0) AS hypotension_count,
    COALESCE(rv.tachycardia_count, 0) AS tachycardia_count,
    COALESCE(rv.hypoxemia_count, 0) AS hypoxemia_count,
    COALESCE(rv.abnormal_rr_count, 0) AS abnormal_rr_count,
    COALESCE(rv.abnormal_temp_count, 0) AS abnormal_temp_count,
    (COALESCE(rv.hypotension_count, 0) +
     COALESCE(rv.tachycardia_count, 0) +
     COALESCE(rv.hypoxemia_count, 0) +
     COALESCE(rv.abnormal_rr_count, 0) +
     COALESCE(rv.abnormal_temp_count, 0)) AS composite_score,
    CASE WHEN rrt.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_rrt
  FROM patients_age pa
  LEFT JOIN abnormal_vitals rv ON pa.subject_id = rv.subject_id AND pa.hadm_id = rv.hadm_id
  LEFT JOIN rrt_flag rrt ON pa.subject_id = rrt.subject_id AND pa.hadm_id = rrt.hadm_id
),

-- Compute 90th percentile of composite score for RRT patients
rrt_percentile AS (
  SELECT
    APPROX_QUANTILES(composite_score, 1000)[OFFSET(900)] AS p90_score
  FROM patient_scores
  WHERE has_rrt = 1
),

-- Compare top decile of RRT patients vs non-RRT patients
comparison AS (
  SELECT
    'top_decile_rrt' AS group_label,
    AVG(CASE WHEN ps.composite_score >= rp.p90_score THEN ps.hypotension_count END) AS avg_hypotension,
    AVG(CASE WHEN ps.composite_score >= rp.p90_score THEN ps.tachycardia_count END) AS avg_tachycardia,
    AVG(CASE WHEN ps.composite_score >= rp.p90_score THEN ps.icu_los END) AS avg_icu_los,
    AVG(CASE WHEN ps.composite_score >= rp.p90_score THEN ps.hospital_expire_flag END) AS mortality_rate
  FROM patient_scores ps
  CROSS JOIN rrt_percentile rp
  WHERE ps.has_rrt = 1

  UNION ALL

  SELECT
    'non_rrt' AS group_label,
    AVG(ps.hypotension_count) AS avg_hypotension,
    AVG(ps.tachycardia_count) AS avg_tachycardia,
    AVG(ps.icu_los) AS avg_icu_los,
    AVG(ps.hospital_expire_flag) AS mortality_rate
  FROM patient_scores ps
  WHERE;