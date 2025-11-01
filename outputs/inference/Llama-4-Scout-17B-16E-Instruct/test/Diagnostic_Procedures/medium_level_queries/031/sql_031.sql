WITH 
  -- Identify female patients with AKI, aged 38-48
  population AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
      p.anchor_age,
      ic.stay_id IS NOT NULL AS icu_use
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    LEFT JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic 
        ON a.hadm_id = ic.hadm_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 38 AND 48
      AND a.dischtime IS NOT NULL  -- Ensure discharge time is not null
  ),

  -- Calculate non-invasive diagnostics per admission
  diagnostics AS (
    SELECT 
      ce.hadm_id,
      COUNT(DISTINCT ce.itemid) AS num_diagnostics
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN 
      `physionet-data.mimiciv_3_1_icu.d_items` di 
        ON ce.itemid = di.itemid
    WHERE 
      di.category = 'Diagnostic'  -- Assuming non-invasive diagnostics are labeled as 'Diagnostic'
      AND ce.valuenum IS NOT NULL  -- Ensure value is numeric
    GROUP BY 
      ce.hadm_id
  )

-- Compare 1-4 vs 5-7 day stays, stratified by ICU use
SELECT 
  CASE 
    WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
  END AS stay_duration,
  p.icu_use,
  AVG(d.num_diagnostics) AS mean_diagnostics,
  MIN(d.num_diagnostics) AS min_diagnostics,
  MAX(d.num_diagnostics) AS max_diagnostics
FROM 
  population p
JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.hadm_id = a.hadm_id
LEFT JOIN 
  diagnostics d 
    ON p.hadm_id = d.hadm_id
GROUP BY 
  stay_duration,
  p.icu_use
ORDER BY 
  stay_duration,
  p.icu_use;