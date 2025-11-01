WITH cohort AS (
  -- Base cohort: 39-49y females with T2DM + HF, LOS >=72h
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
    AND EXISTS (
      -- T2DM (ICD-10 E11.*)
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id 
        AND d.icd_version = '10'
        AND d.icd_code LIKE 'E11.%'
    )
    AND EXISTS (
      -- Heart failure (ICD-10 I50.*)
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id 
        AND d.icd_version = '10'
        AND d.icd_code LIKE 'I50.%'
    )
),

first_72h_insulin AS (
  -- Insulin in first 72h: ICU IV + HOSP SC
  SELECT 
    c.hadm_id,
    -- Basal IV
    COUNTIF(ie.itemid = '225798' AND ie.rate > 0 AND TIMESTAMP_DIFF(ie.endtime, ie.starttime, HOUR) > 0) > 0 AS has_basal_72h,
    -- Bolus IV
    COUNTIF(ie.itemid = '225977' AND ie.amount > 0) > 0 AS has_bolus_72h,
    -- Sliding IV
    COUNTIF(ie.itemid = '225839' AND ie.amount > 0) > 0 AS has_sliding_72h,
    -- Basal SC fallback
    COUNTIF(pr.drug LIKE '%glargine%' OR pr.drug LIKE '%detemir%' OR pr.drug LIKE '%degludec%' 
            AND pr.dose_val_rx > 0) > 0 AS has_basal_sc_72h,
    -- Bolus SC fallback
    COUNTIF((pr.drug LIKE '%aspart%' OR pr.drug LIKE '%lispro%' OR pr.drug LIKE '%regular%') 
            AND pr.dose_val_rx > 0 AND pr.drug NOT LIKE '%sliding%') > 0 AS has_bolus_sc_72h,
    -- Sliding SC fallback
    COUNTIF(pr.drug LIKE '%regular%' AND (pr.form_rx LIKE '%sliding%' OR pr.drug LIKE '%PRN%')) > 0 AS has_sliding_sc_72h
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON c.subject_id = icu.subject_id AND c.hadm_id = icu.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON icu.subject_id = ie.subject_id 
    AND icu.stay_id = ie.stay_id
    AND ie.itemid IN ('225798', '225977', '225839')
    AND ie.starttime >= c.admittime 
    AND ie.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id 
    AND c.hadm_id = pr.hadm_id
    AND pr.drug LIKE '%insulin%'
    AND pr.starttime >= c.admittime 
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id
),

final_48h_insulin AS (
  -- Similar for final 48h
  SELECT 
    c.hadm_id,
    COUNTIF(ie.itemid = '225798' AND ie.rate > 0 AND TIMESTAMP_DIFF(ie.endtime, ie.starttime, HOUR) > 0) > 0 AS has_basal_48h,
    COUNTIF(ie.itemid = '225977' AND ie.amount > 0) > 0 AS has_bolus_48h,
    COUNTIF(ie.itemid = '225839' AND ie.amount > 0) > 0 AS has_sliding_48h,
    COUNTIF(pr.drug LIKE '%glargine%' OR pr.drug LIKE '%detemir%' OR pr.drug LIKE '%degludec%' 
            AND pr.dose_val_rx > 0) > 0 AS has_basal_sc_48h,
    COUNTIF((pr.drug LIKE '%aspart%' OR pr.drug LIKE '%lispro%' OR pr.drug LIKE '%regular%') 
            AND pr.dose_val_rx > 0 AND pr.drug NOT LIKE '%sliding%') > 0 AS has_bolus_sc_48h,
    COUNTIF(pr.drug LIKE '%regular%' AND (pr.form_rx LIKE '%sliding%' OR pr.drug LIKE '%PRN%')) > 0 AS has_sliding_sc_48h
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON c.subject_id = icu.subject_id AND c.hadm_id = icu.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON icu.subject_id = ie.subject_id 
    AND icu.stay_id = ie.stay_id
    AND ie.itemid IN ('225798', '225977', '225839')
    AND ie.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR)
    AND ie.starttime < c.dischtime
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id 
    AND c.hadm_id = pr.hadm_id
    AND pr.drug LIKE '%insulin%'
    AND pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR)
    AND pr.starttime < c.dischtime
  GROUP BY c.hadm_id
),

regimens AS (
  SELECT 
    f.hadm_id,
    -- First 72h regimen
    CASE 
      WHEN (f.has_basal_72h OR f.has_basal_sc_72h) AND (f.has_bolus_72h OR f.has_bolus_sc_72h) 
           AND NOT (f.has_sliding_72h OR f.has_sliding_sc_72h) THEN 'basal_bolus'
      WHEN (f.has_basal_72h OR f.has_basal_sc_72h) AND NOT (f.has_bolus_72h OR f.has_bolus_sc_72h) 
           AND NOT (f.has_sliding_72h OR f.has_sliding_sc_72h) THEN 'basal'
      WHEN NOT (f.has_basal_72h OR f.has_basal_sc_72h) AND (f.has_bolus_72h OR f.has_bolus_sc_72h) 
           AND NOT (f.has_sliding_72h OR f.has_sliding_sc_72h) THEN 'bolus'
      WHEN (f.has_sliding_72h OR f.has_sliding_sc_72h) OR 
           ((f.has_basal_72h OR f.has_basal_sc_72h OR f.has_bolus_72h OR f.has_bolus_sc_72h) 
            AND (f.has_sliding_72h OR f.has_sliding_sc_72h)) THEN 'sliding_scale'
      ELSE 'none'
    END AS regimen_72h,
    -- Final 48h regimen (similar logic)
    CASE 
      WHEN (s.has_basal_48h OR s.has_basal_sc_48h) AND (s.has_bolus_48h OR s.has_bolus_sc_48h) 
           AND NOT (s.has_sliding_48h OR s.has_sliding_sc_48h) THEN 'basal_bolus'
      WHEN (s.has_basal_48h OR s.has_basal_sc_48h) AND NOT (s.has_bolus_48h OR s.has_bolus_sc_48h) 
           AND NOT (s.has_sliding_48h OR s.has_sliding_sc_48h) THEN 'basal'
      WHEN NOT (s.has_basal_48h OR s.has_basal_sc_48h) AND (s.has_bolus_48h OR s.has_bolus_sc_48h) 
           AND NOT (s.has_sliding_48h OR s.has_sliding_sc_48h) THEN 'bolus'
      WHEN (s.has_sliding_48h OR s.has_sliding_sc_48h) OR 
           ((s.has_basal_48h OR s.has_basal_sc_48h OR s.has_bolus_48h OR s.has_bolus_sc_48h) 
            AND (s.has_sliding_48h OR s.has_sliding_sc_48h)) THEN 'sliding_scale'
      ELSE 'none'
    END AS regimen_48h
  FROM first_72h_insulin f
  INNER JOIN final_48h_insulin s ON f.hadm_id = s.hadm_id
)

-- Aggregate percentages and differences (among those initiating any insulin in the window)
SELECT 
  'basal' AS regimen,
  ROUND(100.0 * COUNTIF(regimen_72h = 'basal') / COUNTIF(regimen_72h != 'none'), 1) AS pct_first_72h,
  ROUND(100.0 * COUNTIF(regimen_48h = 'basal') / COUNTIF(regimen_48h != 'none'), 1) AS pct_final_48h,
  ROUND(100.0 * (COUNTIF(regimen_72h = 'basal') / COUNTIF(regimen_72h != 'none') 
                 - COUNTIF(regimen_48h = 'basal') / COUNTIF(regimen_48h != 'none')), 1) AS pct_point_diff
FROM regimens
UNION ALL
SELECT 
  'bolus' AS regimen,
  ROUND(100.0 * COUNTIF(regimen_72h = 'bolus') / COUNTIF(regimen_72h != 'none'), 1) AS pct_first_72h,
  ROUND(100.0 * COUNTIF(regimen_48h = 'bolus') / COUNTIF(regimen_48h != 'none'), 1) AS pct_final_48h,
  ROUND(100.0 * (COUNTIF(regimen_72h = 'bolus') / COUNTIF(regimen_72h != 'none') 
                 - COUNTIF(regimen_48h = 'bolus') / COUNTIF(regimen_48h != 'none')), 1) AS pct_point_diff
FROM regimens
UNION ALL
SELECT 
  'basal_bolus' AS regimen,
  ROUND(100.0 * COUNTIF(regimen_72h = 'basal_bolus') / COUNTIF(regimen_72h != 'none'), 1) AS pct_first_72h,
  ROUND(100.0 * COUNTIF(regimen_48h = 'basal_bolus') / COUNTIF(regimen_48h != 'none'), 1) AS pct_final_48h,
  ROUND(100.0 * (COUNTIF(regimen_72h = 'basal_bolus') / COUNTIF(regimen_72h != 'none') 
                 - COUNTIF(regimen_48h = 'basal_bolus') / COUNTIF(regimen_48h != 'none')), 1) AS pct_point_diff
FROM regimens
UNION ALL
SELECT 
  'sliding_scale' AS regimen,
  ROUND(100.0 * COUNTIF(regimen_72h = 'sliding_scale') / COUNTIF(regimen_72h != 'none'), 1) AS pct_first_72h,
  ROUND(100.0 * COUNTIF(regimen_48h = 'sliding_scale') / COUNTIF(regimen_48h != 'none'), 1) AS pct_final_48h,
  ROUND(100.0 * (COUNTIF(regimen_72h = 'sliding_scale') / COUNTIF(regimen_72h != 'none') 
                 - COUNTIF(regimen_48h = 'sliding_scale') / COUNTIF(regimen_48h != 'none')), 1) AS pct_point_diff
FROM regimens
ORDER BY regimen;