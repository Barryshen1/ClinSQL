WITH qualifying_admissions AS (
  -- Base admissions with demographics and LOS filter
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i  -- Ensure ICU stay
  ON a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND a.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')
    AND a.hospital_expire_flag = 0
    AND DATE_DIFF(a.dischtime, a.admittime, HOUR) >= 96
),

diabetes AS (
  -- Subquery for diabetes diagnosis
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE d.icd_version = '10'
    AND d.icd_code LIKE 'E1[0-4]%'
),

heart_failure AS (
  -- Subquery for heart failure
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE d.icd_version = '10'
    AND d.icd_code LIKE 'I50%'
),

insulin_items AS (
  -- Define insulin itemids (verified from d_items)
  SELECT itemid, category
  FROM UNNEST([
    STRUCT(225798 AS itemid, 'regular' AS category),  -- Regular insulin (sliding/bolus)
    STRUCT(225655 AS itemid, 'aspart' AS category),   -- Aspart (bolus)
    STRUCT(225656 AS itemid, 'lispro' AS category),   -- Lispro (bolus)
    STRUCT(50006 AS itemid, 'glargine' AS category),  -- Glargine (basal)
    STRUCT(50069 AS itemid, 'detemir' AS category)    -- Detemir (basal)
  ])
),

insulin_events AS (
  -- All insulin administrations in ICU
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.itemid,
    ie.starttime,
    ie.endtime,
    ie.amount,
    ii.category
  FROM 
    `physionet-data.mimiciv_3_1_icu.inputevents` ie
  INNER JOIN 
    qualifying_admissions qa
  ON ie.hadm_id = qa.hadm_id
  INNER JOIN 
    insulin_items ii
  ON ie.itemid = ii.itemid
  WHERE 
    CAST(ie.amountuom AS STRING) = 'unit'  -- Standard unit
    AND ie.amount > 0
    AND ie.starttime <= COALESCE(ie.endtime, ie.starttime)  -- Valid times
),

windowed_insulin AS (
  -- Assign events to first/final 48h windows per admission (aggregate across stays)
  SELECT 
    hadm_id,
    window_type,
    SUM(CASE WHEN category IN ('regular', 'aspart', 'lispro') THEN amount ELSE 0 END) AS bolus_amount,
    SUM(CASE WHEN category IN ('glargine', 'detemir') THEN amount ELSE 0 END) AS basal_amount,
    SUM(amount) AS total_amount
  FROM (
    SELECT 
      ie.hadm_id,
      'first_48h' AS window_type,
      ie.amount,
      ii.category
    FROM insulin_events ie
    INNER JOIN qualifying_admissions qa ON ie.hadm_id = qa.hadm_id
    INNER JOIN insulin_items ii ON ie.itemid = ii.itemid
    WHERE 
      ie.starttime >= qa.admittime 
      AND ie.starttime <= TIMESTAMP_ADD(qa.admittime, INTERVAL 48 HOUR)
      AND (ie.endtime IS NULL OR ie.endtime >= qa.admittime)
    
    UNION ALL
    
    SELECT 
      ie.hadm_id,
      'final_48h' AS window_type,
      ie.amount,
      ii.category
    FROM insulin_events ie
    INNER JOIN qualifying_admissions qa ON ie.hadm_id = qa.hadm_id
    INNER JOIN insulin_items ii ON ie.itemid = ii.itemid
    WHERE 
      ie.starttime >= TIMESTAMP_SUB(qa.dischtime, INTERVAL 48 HOUR)
      AND ie.starttime <= qa.dischtime
      AND (ie.endtime IS NULL OR ie.endtime >= TIMESTAMP_SUB(qa.dischtime, INTERVAL 48 HOUR))
  )
  GROUP BY hadm_id, window_type
),

regimens AS (
  -- Classify regimens per window
  SELECT 
    hadm_id,
    window_type,
    CASE 
      WHEN basal_amount > 0 AND bolus_amount = 0 THEN 'basal'
      WHEN bolus_amount > 0 AND basal_amount = 0 THEN 'bolus'
      WHEN basal_amount > 0 AND bolus_amount > 0 THEN 'basal_bolus'
      WHEN total_amount > 0 AND basal_amount = 0 AND bolus_amount = 0 THEN 'sliding_scale'  -- Regular only
      ELSE 'none'
    END AS regimen
  FROM windowed_insulin
),

-- Final qualifying admissions with both diagnoses
final_cohort AS (
  SELECT qa.*
  FROM qualifying_admissions qa
  INNER JOIN diabetes d ON qa.subject_id = d.subject_id AND qa.hadm_id = d.hadm_id
  INNER JOIN heart_failure hf ON qa.subject_id = hf.subject_id AND qa.hadm_id = hf.hadm_id
),

-- Summary: % per regimen and window
summary_stats AS (
  SELECT 
    window_type,
    regimen,
    COUNT(*) AS num_patients,
    COUNT(*) * 100.0 / (SELECT COUNT(DISTINCT hadm_id) FROM final_cohort) AS percentage
  FROM regimens r
  INNER JOIN final_cohort fc ON r.hadm_id = fc.hadm_id
  WHERE r.regimen != 'none'  -- Focus on insulin users for %
  GROUP BY window_type, regimen
  ORDER BY window_type, 
    CASE regimen 
      WHEN 'basal' THEN 1 
      WHEN 'bolus' THEN 2 
      WHEN 'basal_bolus' THEN 3 
      WHEN 'sliding_scale' THEN 4 
    END
),

-- Transitions: Early -> Final
transitions AS (
  SELECT 
    CONCAT(early_regimen, ' → ', final_regimen) AS transition,
    COUNT(*) AS num_transitions,
    COUNT(*) * 100.0 / (SELECT COUNT(DISTINCT hadm_id) FROM final_cohort) AS percentage
  FROM (
    SELECT 
      r1.regimen AS early_regimen,
      r2.regimen AS final_regimen,
      r1.hadm_id
    FROM regimens r1
    INNER JOIN regimens r2 ON r1.hadm_id = r2.hadm_id
    INNER JOIN final_cohort fc ON r1.hadm_id = fc.hadm_id
    WHERE r1.window_type = 'first_48h' 
      AND r2.window_type = 'final_48h'
      AND r1.regimen != 'none' 
      AND r2.regimen != 'none'
  ) t
  GROUP BY transition
  ORDER BY percentage DESC
)

-- Combine both parts
SELECT * FROM summary_stats
UNION ALL
SELECT transition AS window_type, regimen AS regimen, num_transitions AS num_patients, percentage
FROM transitions;