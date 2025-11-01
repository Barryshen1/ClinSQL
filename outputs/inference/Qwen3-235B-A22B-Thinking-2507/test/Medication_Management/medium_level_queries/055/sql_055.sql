WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    -- Calculate exact age at ICU admission using valid timestamp construction
    TIMESTAMP_DIFF(i.intime, TIMESTAMP(DATE(p.anchor_year, 1, 1)), YEAR) + p.anchor_age AS age_at_admission,
    -- ICU LOS in hours
    TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) AS icu_los_hours
  FROM 
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu`.icustays i ON a.hadm_id = i.hadm_id
  -- Get T2DM diagnoses
  INNER JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
    WHERE 
      (icd_version = 10 AND icd_code LIKE 'E11.%') OR
      (icd_version = 9 AND icd_code LIKE '2500%')
  ) t2dm ON a.hadm_id = t2dm.hadm_id
  -- Get heart failure diagnoses
  INNER JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
    WHERE 
      (icd_version = 10 AND icd_code LIKE 'I50.%') OR
      (icd_version = 9 AND icd_code LIKE '428%')
  ) hf ON a.hadm_id = hf.hadm_id
  WHERE
    p.gender = 'F'
    -- Fix age filter using valid timestamp construction
    AND TIMESTAMP_DIFF(i.intime, TIMESTAMP(DATE(p.anchor_year, 1, 1)), YEAR) + p.anchor_age BETWEEN 39 AND 49
    AND TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) >= 72
),

insulin_admin AS (
  SELECT
    c.subject_id,
    c.stay_id,
    ie.starttime,
    -- Classify insulin type
    MAX(CASE WHEN ie.ordercategoryname = 'Continuous IV Insulin' THEN 1 ELSE 0 END) AS is_basal,
    MAX(CASE WHEN ie.ordercategoryname = 'IV Push - Insulin' THEN 1 ELSE 0 END) AS is_bolus,
    MAX(CASE WHEN ie.ordercategoryname = 'Sliding Scale Insulin' THEN 1 ELSE 0 END) AS is_sliding
  FROM
    cohort c
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.inputevents ie 
    ON c.stay_id = ie.stay_id
  WHERE
    ie.ordercategoryname IN ('Continuous IV Insulin', 'IV Push - Insulin', 'Sliding Scale Insulin')
  GROUP BY
    c.subject_id, c.stay_id, ie.starttime
),

time_windows AS (
  SELECT
    c.subject_id,
    c.stay_id,
    -- First 72 hours window flags
    MAX(CASE WHEN ia.starttime <= TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR) AND ia.is_basal = 1 THEN 1 ELSE 0 END) AS first_72h_basal,
    MAX(CASE WHEN ia.starttime <= TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR) AND ia.is_bolus = 1 THEN 1 ELSE 0 END) AS first_72h_bolus,
    MAX(CASE WHEN ia.starttime <= TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR) AND ia.is_sliding = 1 THEN 1 ELSE 0 END) AS first_72h_sliding,
    -- Basal-bolus requires both types
    MAX(CASE WHEN ia.starttime <= TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR) AND ia.is_basal = 1 THEN 1 ELSE 0 END) *
    MAX(CASE WHEN ia.starttime <= TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR) AND ia.is_bolus = 1 THEN 1 ELSE 0 END) AS first_72h_basal_bolus,
    -- Final 48 hours window flags
    MAX(CASE WHEN ia.starttime >= TIMESTAMP_SUB(c.outtime, INTERVAL 48 HOUR) AND ia.is_basal = 1 THEN 1 ELSE 0 END) AS final_48h_basal,
    MAX(CASE WHEN ia.starttime >= TIMESTAMP_SUB(c.outtime, INTERVAL 48 HOUR) AND ia.is_bolus = 1 THEN 1 ELSE 0 END) AS final_48h_bolus,
    MAX(CASE WHEN ia.starttime >= TIMESTAMP_SUB(c.outtime, INTERVAL 48 HOUR) AND ia.is_sliding = 1 THEN 1 ELSE 0 END) AS final_48h_sliding,
    MAX(CASE WHEN ia.starttime >= TIMESTAMP_SUB(c.outtime, INTERVAL 48 HOUR) AND ia.is_basal = 1 THEN 1 ELSE 0 END) *
    MAX(CASE WHEN ia.starttime >= TIMESTAMP_SUB(c.outtime, INTERVAL 48 HOUR) AND ia.is_bolus = 1 THEN 1 ELSE 0 END) AS final_48h_basal_bolus
  FROM
    cohort c
  LEFT JOIN
    insulin_admin ia ON c.subject_id = ia.subject_id AND c.stay_id = ia.stay_id
  GROUP BY
    c.subject_id, c.stay_id
)

SELECT
  -- Basal insulin percentages
  SAFE_DIVIDE(SUM(first_72h_basal), COUNT(*)) * 100 AS pct_first_72h_basal,
  SAFE_DIVIDE(SUM(final_48h_basal), COUNT(*)) * 100 AS pct_final_48h_basal,
  (SAFE_DIVIDE(SUM(final_48h_basal), COUNT(*)) - SAFE_DIVIDE(SUM(first_72h_basal), COUNT(*))) * 100 AS diff_basal,
  
  -- Bolus insulin percentages
  SAFE_DIVIDE(SUM(first_72h_bolus), COUNT(*)) * 100 AS pct_first_72h_bolus,
  SAFE_DIVIDE(SUM(final_48h_bolus), COUNT(*)) * 100 AS pct_final_48h_bolus,
  (SAFE_DIVIDE(SUM(final_48h_bolus), COUNT(*)) - SAFE_DIVIDE(SUM(first_72h_bolus), COUNT(*))) * 100 AS diff_bolus,
  
  -- Basal-bolus percentages
  SAFE_DIVIDE(SUM(first_72h_basal_bolus), COUNT(*)) * 100 AS pct_first_72h_basal_bolus,
  SAFE_DIVIDE(SUM(final_48h_basal_bolus), COUNT(*)) * 100 AS pct_final_48h_basal_bolus,
  (SAFE_DIVIDE(SUM(final_48h_basal_bolus), COUNT(*)) - SAFE_DIVIDE(SUM(first_72h_basal_bolus), COUNT(*))) * 100 AS diff_basal_bolus,
  
  -- Sliding scale percentages
  SAFE_DIVIDE(SUM(first_72h_sliding), COUNT(*)) * 100 AS pct_first_72h_sliding,
  SAFE_DIVIDE(SUM(final_48h_sliding), COUNT(*)) * 100 AS pct_final_48h_sliding,
  (SAFE_DIVIDE(SUM(final_48h_sliding), COUNT(*)) - SAFE_DIVIDE(SUM(first_72h_sliding), COUNT(*))) * 100 AS diff_sliding
FROM
  time_windows;