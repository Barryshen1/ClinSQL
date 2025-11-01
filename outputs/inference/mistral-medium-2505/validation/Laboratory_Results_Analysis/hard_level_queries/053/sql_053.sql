WITH
-- Define our target patient population (male inpatients aged 68-78)
target_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS current_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 68 AND 78
),

-- Get all lab events for our target patients within first 72 hours
patient_labs AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    d.label
  FROM
    target_patients t
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON t.subject_id = l.subject_id AND t.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE
    TIMESTAMP_DIFF(l.charttime, t.admittime, HOUR) <= 72
    AND l.valuenum IS NOT NULL
),

-- Calculate lab instability score components
lab_scores AS (
  SELECT
    subject_id,
    hadm_id,
    -- Creatinine (Cr) - using specific itemid for better accuracy
    MAX(CASE WHEN itemid IN (50912, 50885, 50886) THEN valuenum ELSE NULL END) AS creatinine,
    -- Potassium (K) - using specific itemid
    MAX(CASE WHEN itemid IN (50822, 50971, 50824) THEN valuenum ELSE NULL END) AS potassium,
    -- Platelets - using specific itemid
    MAX(CASE WHEN itemid IN (51265, 51264) THEN valuenum ELSE NULL END) AS platelets,
    -- Hemoglobin (Hgb) - using specific itemid
    MAX(CASE WHEN itemid IN (51221, 51222) THEN valuenum ELSE NULL END) AS hemoglobin,
    -- White Blood Cells (WBC) - using specific itemid
    MAX(CASE WHEN itemid IN (51301, 51300) THEN valuenum ELSE NULL END) AS wbc,
    -- Whole blood potassium - using specific itemid
    MAX(CASE WHEN itemid IN (50824) THEN valuenum ELSE NULL END) AS whole_blood_k
  FROM
    patient_labs
  GROUP BY
    subject_id, hadm_id
),

-- Calculate composite lab instability score (simplified example)
patient_scores AS (
  SELECT
    subject_id,
    hadm_id,
    -- Simple example score - in practice this would be more sophisticated
    (COALESCE(creatinine, 1) * 0.1 +
     COALESCE(potassium, 4) * 0.5 +
     (100000 / COALESCE(NULLIF(platelets, 0), 1)) * 0.2 +
     (15 - COALESCE(hemoglobin, 10)) * 0.3 +
     COALESCE(wbc, 5) * 0.1 +
     COALESCE(whole_blood_k, 4) * 0.4) AS instability_score
  FROM
    lab_scores
),

-- Calculate 90th percentile score (simplified approach)
percentile_90 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_score
  FROM
    patient_scores
),

-- Identify top-tier patients (above 90th percentile)
top_tier_patients AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.instability_score,
    t.hospital_expire_flag,
    t.los_hours,
    l.creatinine,
    l.potassium,
    l.platelets,
    l.hemoglobin,
    l.wbc,
    l.whole_blood_k
  FROM
    patient_scores p
  JOIN
    target_patients t ON p.subject_id = t.subject_id AND p.hadm_id = t.hadm_id
  JOIN
    lab_scores l ON p.subject_id = l.subject_id AND p.hadm_id = l.hadm_id
  CROSS JOIN
    percentile_90 p90
  WHERE
    p.instability_score > p90.p90_score
),

-- Calculate metrics for all inpatients (for comparison)
all_inpatients AS (
  SELECT
    AVG(CASE WHEN t.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate,
    AVG(t.los_hours) AS avg_los_hours,
    AVG(l.creatinine) AS avg_creatinine,
    AVG(l.potassium) AS avg_potassium,
    AVG(l.platelets) AS avg_platelets,
    AVG(l.hemoglobin) AS avg_hemoglobin,
    AVG(l.wbc) AS avg_wbc,
    AVG(l.whole_blood_k) AS avg_whole_blood_k
  FROM
    lab_scores l
  JOIN
    target_patients t ON l.subject_id = t.subject_id AND l.hadm_id = t.hadm_id
)

-- Final results
SELECT
  -- 90th percentile score
  p90.p90_score AS ninetieth_percentile_score,

  -- Top-tier patient metrics
  AVG(CASE WHEN t.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS top_tier_mortality_rate,
  AVG(t.los_hours) AS top_tier_avg_los_hours,
  AVG(t.creatinine) AS top_tier_avg_creatinine,
  AVG(t.potassium) AS top_tier_avg_potassium,
  AVG(t.platelets) AS top_tier_avg_platelets,
  AVG(t.hemoglobin) AS top_tier_avg_hemoglobin,
  AVG(t.wbc) AS top_tier_avg_wbc,
  AVG(t.whole_blood_k) AS top_tier_avg_whole_blood_k,

  -- Comparison with all inpatients
  a.mortality_rate AS all_inpatients_mortality_rate,
  a.avg_los_hours AS all_inpatients_avg_los_hours,
  a.avg_creatinine AS all_inpatients_avg_creatinine,
  a.avg_potassium AS all_inpatients_avg_potassium,
  a.avg_platelets AS all_inpatients_avg_platelets,
  a.avg_hemoglobin AS all_inpatients_avg_hemoglobin,
  a.avg_wbc AS all_inpatients_avg_wbc,
  a.avg_whole_blood_k AS all_inpatients_avg_whole_blood_k

FROM
  top_tier_patients t
CROSS JOIN
  percentile_90 p90
CROSS JOIN
  all_inpatients a;