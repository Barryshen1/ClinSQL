WITH patients_age AS (
  SELECT
    subject_id,
    anchor_age,
    anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'M'
),
admissions_with_age AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), DAY) / 365.25 AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_age p ON a.subject_id = p.subject_id
),
diabetes_hf AS (
  SELECT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%diabetes%'
  GROUP BY di.hadm_id
  HAVING COUNT(*) >= 1
  INTERSECT
  SELECT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%heart failure%'
    AND LOWER(d.long_title) LIKE '%acute%'
  GROUP BY di.hadm_id
  HAVING COUNT(*) >= 1
),
cohort AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM admissions_with_age a
  INNER JOIN diabetes_hf dh ON a.hadm_id = dh.hadm_id
  WHERE a.age_at_admit >= 51 AND a.age_at_admit <= 61
),
insulin_admin AS (
  SELECT
    e.hadm_id,
    ed.administration_type,
    e.charttime
  FROM `physionet-data.mimiciv_3_1_hosp`.emar e
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.emar_detail ed
    ON e.emar_id = ed.emar_id
  WHERE ed.administration_type IN ('Basal', 'Bolus', 'Sliding Scale')
    AND e.charttime IS NOT NULL
),
regimen_windows AS (
  SELECT
    c.hadm_id,
    -- First 24h: admittime to admittime + 24h
    MAX(CASE WHEN i.charttime >= c.admittime 
              AND i.charttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
              AND i.administration_type = 'Basal' THEN 1 ELSE 0 END) AS basal_first_24h,
    MAX(CASE WHEN i.charttime >= c.admittime 
              AND i.charttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
              AND i.administration_type = 'Bolus' THEN 1 ELSE 0 END) AS bolus_first_24h,
    MAX(CASE WHEN i.charttime >= c.admittime 
              AND i.charttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
              AND i.administration_type = 'Sliding Scale' THEN 1 ELSE 0 END) AS sliding_scale_first_24h,
    -- Final 12h: dischtime - 12h to dischtime
    MAX(CASE WHEN i.charttime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)
              AND i.charttime <= c.dischtime
              AND i.administration_type = 'Basal' THEN 1 ELSE 0 END) AS basal_final_12h,
    MAX(CASE WHEN i.charttime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)
              AND i.charttime <= c.dischtime
              AND i.administration_type = 'Bolus' THEN 1 ELSE 0 END) AS bolus_final_12h,
    MAX(CASE WHEN i.charttime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)
              AND i.charttime <= c.dischtime
              AND i.administration_type = 'Sliding Scale' THEN 1 ELSE 0 END) AS sliding_scale_final_12h
  FROM cohort c
  LEFT JOIN insulin_admin i ON c.hadm_id = i.hadm_id
  GROUP BY c.hadm_id, c.admittime, c.dischtime
),
regimen_summary AS (
  SELECT
    -- Basal-Bolus: both Basal and Bolus
    AVG(CAST((basal_first_24h = 1 AND bolus_first_24h = 1) AS INT64)) * 100 AS basal_bolus_first_24h_pct,
    AVG(CAST((basal_final_12h = 1 AND bolus_final_12h = 1) AS INT64)) * 100 AS basal_bolus_final_12h_pct,
    -- Basal (any)
    AVG(CAST(basal_first_24h AS INT64)) * 100 AS basal_first_24h_pct,
    AVG(CAST(basal_final_12h AS INT64)) * 100 AS basal_final_12h_pct,
    -- Bolus (any)
    AVG(CAST(bolus_first_24h AS INT64)) * 100 AS bolus_first_24h_pct,
    AVG(CAST(bolus_final_12h AS INT64)) * 100 AS bolus_final_12h_pct,
    -- Sliding Scale (any)
    AVG(CAST(sliding_scale_first_24h AS INT64)) * 100 AS sliding_scale_first_24h_pct,
    AVG(CAST(sliding_scale_final_12h AS INT64)) * 100 AS sliding_scale_final_12h_pct
  FROM regimen_windows
)
SELECT
  basal_bolus_first_24h_pct,
  basal_bolus_final_12h_pct,
  basal_bolus_final_12h_pct - basal_bolus_first_24h_pct AS basal_bolus_pp_change,
  basal_first_24h_pct,
  basal_final_12h_pct,
  basal_final_12h_pct - basal_first_24h_pct AS basal_pp_change,
  bolus_first_24h_pct,
  bolus_final_12h_pct,
  bolus_final_12h_pct - bolus_first_24h_pct AS bolus_pp_change,
  sliding_scale_first_24h_pct,
  sliding_scale_final_12h_pct,
  sliding_scale_final_12h_pct - sliding_scale_first_24h_pct AS sliding_scale_pp_change
FROM regimen_summary;