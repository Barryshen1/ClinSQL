WITH cohort AS (
  -- Females 83-93 with T2DM and HF
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.hadm_id IN (
      -- T2DM: ICD10 E11* or ICD9 250.x0 or 250.x2
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE (icd_version = 10 AND icd_code LIKE 'E11%')
         OR (icd_version = 9 AND icd_code LIKE '250%' AND (icd_code LIKE '%0' OR icd_code LIKE '%2'))
    )
    AND a.hadm_id IN (
      -- HF: ICD10 I50* or ICD9 428%
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE (icd_version = 10 AND icd_code LIKE 'I50%')
         OR (icd_version = 9 AND icd_code LIKE '428%')
    )
),
icu_stays AS (
  -- Get first ICU stay for each admission
  SELECT subject_id, hadm_id, stay_id, intime, outtime
  FROM (
    SELECT 
        subject_id, hadm_id, stay_id, intime, outtime,
        ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) 
  WHERE rn = 1
),
insulin_events AS (
  -- Get insulin events from inputevents for ICU stays
  SELECT 
    i.subject_id, i.hadm_id, i.stay_id,
    i.starttime, i.endtime,
    d.label,
    CASE 
      WHEN d.label LIKE '%glargine%' OR d.label LIKE '%detemir%' OR d.label LIKE '%NPH%' 
           OR d.label LIKE '%degludec%' THEN 'basal'
      WHEN d.label LIKE '%lispro%' OR d.label LIKE '%aspart%' OR d.label LIKE '%regular%'
           OR d.label LIKE '%glulisine%' THEN 'bolus'
      WHEN d.label LIKE '%sliding%' OR d.label LIKE '%scale%' THEN 'sliding'
      ELSE 'other'
    END AS insulin_type
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
  INNER JOIN icu_stays s 
    ON i.stay_id = s.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON i.itemid = d.itemid
  WHERE d.category LIKE '%insulin%'
    AND i.amount > 0
),
first_48h AS (
  -- First 48 hours from admission
  SELECT subject_id, hadm_id,
    MAX(CASE WHEN insulin_type = 'basal' THEN 1 ELSE 0 END) AS basal_initiated,
    MAX(CASE WHEN insulin_type = 'bolus' THEN 1 ELSE 0 END) AS bolus_initiated,
    MAX(CASE WHEN insulin_type = 'sliding' THEN 1 ELSE 0 END) AS sliding_initiated
  FROM insulin_events i
  INNER JOIN cohort c 
    ON i.hadm_id = c.hadm_id
  WHERE i.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY subject_id, hadm_id
),
final_12h AS (
  -- Final 12 hours of stay (only for patients with sufficient length of stay)
  SELECT subject_id, hadm_id,
    MAX(CASE WHEN insulin_type = 'basal' THEN 1 ELSE 0 END) AS basal_initiated,
    MAX(CASE WHEN insulin_type = 'bolus' THEN 1 ELSE 0 END) AS bolus_initiated,
    MAX(CASE WHEN insulin_type = 'sliding' THEN 1 ELSE 0 END) AS sliding_initiated
  FROM insulin_events i
  INNER JOIN cohort c 
    ON i.hadm_id = c.hadm_id
  WHERE i.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime
  GROUP BY subject_id, hadm_id
),
basal_bolus AS (
  -- Identify basal-bolus: both basal and bolus in the same window
  SELECT 
    COALESCE(f.subject_id, l.subject_id) AS subject_id,
    COALESCE(f.hadm_id, l.hadm_id) AS hadm_id,
    CASE WHEN f.basal_initiated = 1 AND f.bolus_initiated = 1 THEN 1 ELSE 0 END AS basal_bolus_48h,
    CASE WHEN l.basal_initiated = 1 AND l.bolus_initiated = 1 THEN 1 ELSE 0 END AS basal_bolus_12h
  FROM first_48h f
  FULL JOIN final_12h l
    ON f.subject_id = l.subject_id AND f.hadm_id = l.hadm_id
)
SELECT 
  COUNT(DISTINCT cohort.hadm_id) AS total_patients,
  -- First 48h
  ROUND(100 * SUM(COALESCE(f.basal_initiated, 0)) / COUNT(DISTINCT cohort.hadm_id), 2) AS pct_basal_48h,
  ROUND(100 * SUM(COALESCE(f.bolus_initiated, 0)) / COUNT(DISTINCT cohort.hadm_id), 2) AS pct_bolus_48h,
  ROUND(100 * SUM(COALESCE(bb.basal_bolus_48h, 0)) / COUNT(DISTINCT cohort.hadm_id), 2) AS pct_basal_bolus_48h,
  ROUND(100 * SUM(COALESCE(f.sliding_initiated, 0)) / COUNT(DISTINCT cohort.hadm_id), 2) AS pct_sliding_48h,
  -- Final 12h
  ROUND(100 * SUM(COALESCE(l.basal_initiated, 0)) / COUNT(DISTINCT cohort.hadm_id), 2) AS pct_basal_12h,
  ROUND(100 * SUM(COALESCE(l.bolus_initiated, 0)) / COUNT(DISTINCT cohort.hadm_id), 2) AS pct_bolus_12h,
  ROUND(100 * SUM(COALESCE(bb.basal_bolus_12h, 0)) / COUNT(DISTINCT cohort.hadm_id), 2) AS pct_basal_bolus_12h,
  ROUND(100 * SUM(COALESCE(l.sliding_initiated, 0)) / COUNT(DISTINCT cohort.hadm_id), 2) AS pct_sliding_12h,
  -- Net change
  ROUND(100 * (SUM(COALESCE(l.basal_initiated, 0)) - SUM(COALESCE(f.basal_initiated, 0))) / COUNT(DISTINCT cohort.hadm_id), 2) AS net_change_basal,
  ROUND(100 * (SUM(COALESCE(l.bolus_initiated, 0)) - SUM(COALESCE(f.bolus_initiated, 0))) / COUNT(DISTINCT cohort.hadm_id), 2) AS net_change_bolus,
  ROUND(100 * (SUM(COALESCE(bb.basal_bolus_12h, 0)) - SUM(COALESCE(bb.basal_bolus_48h, 0))) / COUNT(DISTINCT cohort.hadm_id), 2) AS net_change_basal_bolus,
  ROUND(100 * (SUM(COALESCE(l.sliding_initiated, 0)) - SUM(COALESCE(f.sliding_initiated, 0))) / COUNT(DISTINCT cohort.hadm_id), 2) AS net_change_sliding
FROM cohort
LEFT JOIN first_48h f ON cohort.hadm_id = f.hadm_id
LEFT JOIN final_12h l ON cohort.hadm_id = l.hadm_id
LEFT JOIN basal_bolus bb ON cohort.hadm_id = bb.hadm_id;