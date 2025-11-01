WITH cohort AS (
  -- Base cohort: females 81-91
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) / 1.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND a.admission_type != 'OBSERVATION'  -- Inpatients only
    AND a.hospital_expire_flag = 0  -- Exclude deaths if needed, but keep for generality
),

diagnoses AS (
  -- Add T2DM (E11.*) and heart failure (I50.*)
  SELECT 
    c.*,
    d.icd_code
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
  WHERE (d.icd_code LIKE 'E11.%' OR d.icd_code LIKE 'I50.%')
    AND d.icd_version = 10  -- ICD-10 preferred (fixed type: INT64)
),

qualifying_adms AS (
  -- Admissions with both conditions (at least one E11 and one I50)
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    los_days
  FROM (
    SELECT 
      hadm_id,
      admittime,
      dischtime,
      los_days,
      STRING_AGG(icd_code, ',') OVER (PARTITION BY hadm_id) AS all_icds
    FROM diagnoses
    GROUP BY hadm_id, admittime, dischtime, los_days
  )
  WHERE all_icds LIKE '%E11.%' AND all_icds LIKE '%I50.%'
    AND los_days >= 2  -- Ensure valid late window (48h)
),

prescriptions_filtered AS (
  -- All relevant oral antidiabetics for qualifying admissions
  SELECT DISTINCT
    q.hadm_id,
    q.admittime,
    q.dischtime,
    pres.drug,
    pres.starttime
  FROM qualifying_adms q
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON q.hadm_id = pres.hadm_id
  WHERE (
    -- Metformin
    pres.drug LIKE '%metformin%' OR
    -- Sulfonylurea
    pres.drug LIKE '%glipizide%' OR pres.drug LIKE '%glyburide%' OR 
    pres.drug LIKE '%glimepiride%' OR pres.drug LIKE '%chlorpropamide%' OR
    -- DPP4
    pres.drug LIKE '%sitagliptin%' OR pres.drug LIKE '%saxagliptin%' OR 
    pres.drug LIKE '%linagliptin%' OR pres.drug LIKE '%alogliptin%' OR
    -- SGLT2
    pres.drug LIKE '%canagliflozin%' OR pres.drug LIKE '%dapagliflozin%' OR 
    pres.drug LIKE '%empagliflozin%' OR pres.drug LIKE '%ertugliflozin%' OR
    -- TZD
    pres.drug LIKE '%pioglitazone%' OR pres.drug LIKE '%rosiglitazone%'
  )
    AND pres.drug NOT LIKE '%injection%'  -- Prefer oral (exclude injectables if specified)
),

drug_classes AS (
  -- Assign classes
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    starttime,
    CASE 
      WHEN drug LIKE '%metformin%' THEN 'Metformin'
      WHEN drug LIKE '%glipizide%' OR drug LIKE '%glyburide%' OR 
           drug LIKE '%glimepiride%' OR drug LIKE '%chlorpropamide%' THEN 'Sulfonylurea'
      WHEN drug LIKE '%sitagliptin%' OR drug LIKE '%saxagliptin%' OR 
           drug LIKE '%linagliptin%' OR drug LIKE '%alogliptin%' THEN 'DPP4'
      WHEN drug LIKE '%canagliflozin%' OR drug LIKE '%dapagliflozin%' OR 
           drug LIKE '%empagliflozin%' OR drug LIKE '%ertugliflozin%' THEN 'SGLT2'
      WHEN drug LIKE '%pioglitazone%' OR drug LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM prescriptions_filtered
),

windows AS (
  -- Early: first 72h; Late: last 48h
  SELECT 
    hadm_id,
    drug_class,
    CASE 
      WHEN starttime >= admittime 
       AND starttime < TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) 
      THEN 'Early_72h'
      WHEN starttime >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) 
       AND starttime < dischtime 
      THEN 'Late_48h'
      ELSE NULL
    END AS time_window
  FROM drug_classes
  WHERE time_window IS NOT NULL  -- Only in-window starts (moved to SELECT, filter here)
),

prevalence AS (
  SELECT 
    drug_class,
    time_window,
    COUNT(DISTINCT hadm_id) AS exposed_adms
  FROM (
    -- All hadm-time combos, with exposure flag
    SELECT 
      w.drug_class,
      w.time_window,
      w.hadm_id
    FROM windows w
    UNION ALL
    -- Add non-exposed for denominator (per window)
    SELECT 
      NULL AS drug_class,
      'Early_72h' AS time_window,
      q.hadm_id
    FROM qualifying_adms q
    WHERE NOT EXISTS (
      SELECT 1 FROM windows w2 
      WHERE w2.hadm_id = q.hadm_id AND w2.time_window = 'Early_72h'
    )
    UNION ALL
    SELECT 
      NULL AS drug_class,
      'Late_48h' AS time_window,
      q.hadm_id
    FROM qualifying_adms q
    WHERE NOT EXISTS (
      SELECT 1 FROM windows w2 
      WHERE w2.hadm_id = q.hadm_id AND w2.time_window = 'Late_48h'
    )
  )
  GROUP BY drug_class, time_window
),

total_cohort AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_adms FROM qualifying_adms
),

final_stats AS (
  SELECT 
    COALESCE(p.drug_class, 'None') AS drug_class,
    p.time_window,
    ROUND((p.exposed_adms * 100.0 / t.total_adms), 2) AS prevalence_pct
  FROM prevalence p
  CROSS JOIN total_cohort t
)

-- Pivot for pp difference (late - early)
SELECT 
  drug_class,
  MAX(CASE WHEN time_window = 'Early_72h' THEN prevalence_pct END) AS early_72h_pct,
  MAX(CASE WHEN time_window = 'Late_48h' THEN prevalence_pct END) AS late_48h_pct,
  ROUND(
    MAX(CASE WHEN time_window = 'Late_48h' THEN prevalence_pct END) - 
    MAX(CASE WHEN time_window = 'Early_72h' THEN prevalence_pct END), 
    2
  ) AS pp_difference
FROM final_stats
WHERE drug_class != 'None'  -- Exclude 'None' row
GROUP BY drug_class
ORDER BY pp_difference DESC;