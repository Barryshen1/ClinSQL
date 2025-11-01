WITH cohort AS (
  -- Define cohort: males 51-61 with diabetes and AHF
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT', 'OBSERVATION')
    AND d.icd_version = '10'  -- ICD-10 only
    AND (d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR d.icd_code LIKE 'E1[0-3]%')  -- Diabetes (refined)
    AND d.icd_code LIKE 'I50%'  -- Acute heart failure
    AND icd.long_title IS NOT NULL  -- Valid code
),

insulin_items AS (
  -- Get insulin itemids from d_items (filter to numeric only)
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%insulin%'
    AND category = 'Medications'
    AND SAFE_CAST(itemid AS INT64) IS NOT NULL
),

icu_stays AS (
  -- ICU stays for cohort admissions
  SELECT c.subject_id, c.hadm_id, i.stay_id, i.intime, i.outtime
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
),

insulin_events AS (
  -- Insulin input events with time windows
  SELECT 
    s.subject_id, s.hadm_id, s.stay_id,
    ie.starttime,
    s.intime,
    s.outtime,
    -- Window flags
    CASE WHEN ie.starttime >= s.intime 
         AND ie.starttime < TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR) 
         THEN 1 ELSE 0 END AS in_first_24h,
    CASE WHEN ie.starttime >= TIMESTAMP_SUB(s.outtime, INTERVAL 12 HOUR) 
         AND ie.starttime < s.outtime 
         THEN 1 ELSE 0 END AS in_final_12h,
    -- Heuristic regimen classification (per event; aggregate later; note: simplistic, Basal-Bolus is proxy)
    ie.itemid,
    ie.amount, ie.amountuom, ie.rate, ie.rateuom,
    CASE 
      WHEN ie.rate > 0 AND ie.rate < 2 AND ie.amountuom = 'unit'  -- Sustained low rate
        THEN 'Basal'
      WHEN ie.amount >= 5 AND (ie.rate IS NULL OR ie.rate = 0) AND ie.amountuom = 'unit'  -- Bolus
        THEN 'Bolus'
      WHEN ie.rate > 0 AND ie.rate >= 2 AND ie.rateuom = 'unit/hour'  -- Variable high rate (sliding proxy)
        THEN 'Sliding-scale'
      ELSE 'Other'
    END AS regimen
  FROM icu_stays s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON s.stay_id = ie.stay_id
  INNER JOIN insulin_items ii 
    ON CAST(ii.itemid AS INT64) = ie.itemid
  WHERE (ie.amountuom IN ('unit', 'ml') OR ie.rateuom IN ('unit/hour', 'ml/hour'))
    AND ie.statusdescription != 'Rewritten'  -- Valid orders
),

regimen_flags AS (
  -- Aggregate to admission-level flags per window and regimen
  SELECT 
    hadm_id,
    -- First 24h
    MAX(CASE WHEN in_first_24h = 1 AND regimen = 'Basal' THEN 1 ELSE 0 END) AS basal_first,
    MAX(CASE WHEN in_first_24h = 1 AND regimen = 'Bolus' THEN 1 ELSE 0 END) AS bolus_first,
    MAX(CASE WHEN in_first_24h = 1 AND regimen = 'Sliding-scale' THEN 1 ELSE 0 END) AS sliding_first,
    MAX(CASE WHEN in_first_24h = 1 AND (regimen = 'Basal' OR regimen = 'Bolus') THEN 1 ELSE 0 END) AS basal_bolus_first,  -- Proxy for combo
    MAX(CASE WHEN in_first_24h = 1 THEN 1 ELSE 0 END) AS any_insulin_first,  -- For None calc
    -- Final 12h
    MAX(CASE WHEN in_final_12h = 1 AND regimen = 'Basal' THEN 1 ELSE 0 END) AS basal_final,
    MAX(CASE WHEN in_final_12h = 1 AND regimen = 'Bolus' THEN 1 ELSE 0 END) AS bolus_final,
    MAX(CASE WHEN in_final_12h = 1 AND regimen = 'Sliding-scale' THEN 1 ELSE 0 END) AS sliding_final,
    MAX(CASE WHEN in_final_12h = 1 AND (regimen = 'Basal' OR regimen = 'Bolus') THEN 1 ELSE 0 END) AS basal_bolus_final,
    MAX(CASE WHEN in_final_12h = 1 THEN 1 ELSE 0 END) AS any_insulin_final
  FROM insulin_events
  GROUP BY hadm_id
),

total_count AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_admissions
  FROM regimen_flags
),

prevalences AS (
  SELECT 
    'Basal' AS regimen,
    tc.total_admissions,
    AVG(COALESCE(basal_first, 0)) * 100 AS first_24h_pct,
    AVG(COALESCE(basal_final, 0)) * 100 AS final_12h_pct,
    (AVG(COALESCE(basal_final, 0)) - AVG(COALESCE(basal_first, 0))) * 100 AS pp_change
  FROM regimen_flags rf
  CROSS JOIN total_count tc
  GROUP BY tc.total_admissions
  UNION ALL
  SELECT 
    'Bolus' AS regimen,
    tc.total_admissions,
    AVG(COALESCE(bolus_first, 0)) * 100 AS first_24h_pct,
    AVG(COALESCE(bolus_final, 0)) * 100 AS final_12h_pct,
    (AVG(COALESCE(bolus_final, 0)) - AVG(COALESCE(bolus_first, 0))) * 100 AS pp_change
  FROM regimen_flags rf
  CROSS JOIN total_count tc
  GROUP BY tc.total_admissions
  UNION ALL
  SELECT 
    'Sliding-scale' AS regimen,
    tc.total_admissions,
    AVG(COALESCE(sliding_first, 0)) * 100 AS first_24h_pct,
    AVG(COALESCE(sliding_final, 0)) * 100 AS final_12h_pct,
    (AVG(COALESCE(sliding_final, 0)) - AVG(COALESCE(sliding_first, 0))) * 100 AS pp_change
  FROM regimen_flags rf
  CROSS JOIN total_count tc
  GROUP BY tc.total_admissions
  UNION ALL
  SELECT 
    'Basal-Bolus' AS regimen,
    tc.total_admissions,
    AVG(COALESCE(basal_bolus_first, 0)) * 100 AS first_24h_pct,
    AVG(COALESCE(basal_bolus_final, 0)) * 100 AS final_12h_pct,
    (AVG(COALESCE(basal_bolus_final, 0)) - AVG(COALESCE(basal_bolus_first, 0))) * 100 AS pp_change
  FROM regimen_flags rf
  CROSS JOIN total_count tc
  GROUP BY tc.total_admissions
  UNION ALL
  SELECT 
    'None' AS regimen,
    tc.total_admissions,
    AVG(1 - COALESCE(any_insulin_first, 0)) * 100 AS first_24h_pct,
    AVG(1 - COALESCE(any_insulin_final, 0)) * 100 AS final_12h_pct,
    (AVG(1 - COALESCE(any_insulin_final, 0)) - AVG(1 - COALESCE(any_insulin_first, 0))) * 100 AS pp_change
  FROM regimen_flags rf
  CROSS JOIN total_count tc
  GROUP BY tc.total_admissions
)

SELECT 
  regimen,
  ROUND(first_24h_pct, 2) AS first_24h_prevalence_pct,
  ROUND(final_12h_pct, 2) AS final_12h_prevalence_pct,
  ROUND(pp_change, 2) AS percentage_point_change,
  total_admissions
FROM prevalences
ORDER BY 
  CASE regimen 
    WHEN 'Basal-Bolus' THEN 1
    WHEN 'Basal' THEN 2
    WHEN 'Bolus' THEN 3
    WHEN 'Sliding-scale' THEN 4
    WHEN 'None' THEN 5
  END;