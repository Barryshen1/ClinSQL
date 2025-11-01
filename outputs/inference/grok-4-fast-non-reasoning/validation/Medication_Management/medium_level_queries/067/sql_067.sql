WITH cohort AS (
  -- Filter men aged 64-74 with inpatient admissions
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.admission_type != 'OBSERVATION'  -- Inpatient only
),

windows AS (
  -- Define time windows per hadm_id
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    admittime AS first_12h_start,
    admittime + INTERVAL 12 HOUR AS first_12h_end,
    dischtime - INTERVAL 48 HOUR AS final_48h_start,
    dischtime AS final_48h_end
  FROM 
    cohort
  WHERE 
    -- Exclude short stays that can't support both windows
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) >= 48  -- At least 48h for final window
),

admin_events AS (
  -- Join emar administrations to cohort
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    e.charttime,
    LOWER(e.medication) AS medication_lower
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.emar` e
  ON 
    c.subject_id = e.subject_id 
    AND c.hadm_id = e.hadm_id
  WHERE 
    e.medication IS NOT NULL 
    AND TRIM(e.medication) != ''
),

drug_classifications AS (
  -- Classify administrations by antidiabetic class
  SELECT 
    ae.hadm_id,
    ae.charttime,
    CASE 
      WHEN ae.medication_lower LIKE '%insulin%' THEN 'Insulin'
      WHEN ae.medication_lower LIKE '%metformin%' THEN 'Metformin'
      WHEN ae.medication_lower LIKE '%glyburide%' 
        OR ae.medication_lower LIKE '%glipizide%' 
        OR ae.medication_lower LIKE '%glimepiride%' 
        OR ae.medication_lower LIKE '%tolbutamide%' 
        OR ae.medication_lower LIKE '%chlorpropamide%' THEN 'Sulfonylureas'
      WHEN ae.medication_lower LIKE '%sitagliptin%' 
        OR ae.medication_lower LIKE '%saxagliptin%' 
        OR ae.medication_lower LIKE '%linagliptin%' 
        OR ae.medication_lower LIKE '%alogliptin%' THEN 'DPP-4'
      WHEN ae.medication_lower LIKE '%canagliflozin%' 
        OR ae.medication_lower LIKE '%dapagliflozin%' 
        OR ae.medication_lower LIKE '%empagliflozin%' 
        OR ae.medication_lower LIKE '%ertugliflozin%' THEN 'SGLT2'
      WHEN ae.medication_lower LIKE '%exenatide%' 
        OR ae.medication_lower LIKE '%liraglutide%' 
        OR ae.medication_lower LIKE '%dulaglutide%' 
        OR ae.medication_lower LIKE '%semaglutide%' 
        OR ae.medication_lower LIKE '%albiglutide%' THEN 'GLP-1'
      WHEN ae.medication_lower LIKE '%pioglitazone%' 
        OR ae.medication_lower LIKE '%rosiglitazone%' THEN 'TZDs'
      ELSE NULL
    END AS drug_class
  FROM 
    admin_events ae
  WHERE 
    ae.medication_lower IS NOT NULL
),

initiations AS (
  -- Detect first initiation per hadm/class/window (1 if initiated in window)
  SELECT 
    w.hadm_id,
    dc.drug_class,
    'First 12h' AS time_window,
    MIN(CASE 
      WHEN dc.charttime >= w.first_12h_start AND dc.charttime < w.first_12h_end 
      THEN dc.charttime 
      END) AS first_time
  FROM 
    windows w
  INNER JOIN 
    drug_classifications dc
  ON 
    w.hadm_id = dc.hadm_id
  WHERE 
    dc.drug_class IS NOT NULL
  GROUP BY 
    w.hadm_id, dc.drug_class

  UNION ALL

  SELECT 
    w.hadm_id,
    dc.drug_class,
    'Final 48h' AS time_window,
    MIN(CASE 
      WHEN dc.charttime >= w.final_48h_start AND dc.charttime < w.final_48h_end 
      THEN dc.charttime 
      END) AS first_time
  FROM 
    windows w
  INNER JOIN 
    drug_classifications dc
  ON 
    w.hadm_id = dc.hadm_id
  WHERE 
    dc.drug_class IS NOT NULL
  GROUP BY 
    w.hadm_id, dc.drug_class
),

initiated_flags AS (
  -- Flag initiations (1 if first_time is not null, i.e., occurred in window)
  SELECT 
    hadm_id,
    drug_class,
    time_window,
    CASE WHEN first_time IS NOT NULL THEN 1 ELSE 0 END AS initiated
  FROM 
    initiations
)

-- Aggregate to percentages
SELECT 
  ifi.drug_class,
  ifi.time_window,
  ROUND(SUM(COALESCE(ifi.initiated, 0)) * 100.0 / COUNT(DISTINCT w.hadm_id), 2) AS initiation_percentage,
  COUNT(DISTINCT w.hadm_id) AS total_stays
FROM 
  initiated_flags ifi
INNER JOIN 
  windows w
ON 
  ifi.hadm_id = w.hadm_id
GROUP BY 
  ifi.drug_class, ifi.time_window
ORDER BY 
  ifi.drug_class, 
  CASE WHEN ifi.time_window = 'First 12h' THEN 1 ELSE 2 END;