WITH 
-- Filter patients
patients_filter AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 51 AND 61
),

-- Identify diabetes and acute heart failure
diagnoses_filter AS (
  SELECT 
    subject_id, 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_code IN (
      '250.0', '250.1', '250.2', '250.3', '250.4', '250.5', '250.6', '250.7', '250.8', '250.9', 
      '402.01', '402.11', '402.21', '402.31', '402.41', '402.91', '404.01', '404.11', 
      '404.21', '404.31', '404.41', '404.91', '428.0'
    )
),

-- Identify insulin regimens
insulin_regimens AS (
  SELECT 
    p.subject_id, 
    p.hadm_id, 
    ph.starttime, 
    ph.stoptime, 
    ph.medication
  FROM 
    patients_filter p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
  ON 
    p.hadm_id = ph.hadm_id
  WHERE 
    ph.medication LIKE '%insulin%'
),

-- Determine time periods
time_periods AS (
  SELECT 
    hadm_id, 
    admittime, 
    dischtime,
    TIMESTAMP_ADD(admittime, INTERVAL 24 HOUR) AS first_24h_end,
    TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR) AS final_12h_start
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Calculate total patients with diabetes and acute heart failure
total_patients AS (
  SELECT 
    COUNT(DISTINCT df.hadm_id) AS total
  FROM 
    diagnoses_filter df
  JOIN 
    patients_filter pf ON df.hadm_id = pf.hadm_id
),

-- Calculate prevalence and percentage-point change for each regimen
regimen_prevalence AS (
  SELECT 
    tp.hadm_id,
    ir.medication,
    CASE 
      WHEN ir.starttime BETWEEN tp.admittime AND tp.first_24h_end THEN 'first_24h'
      WHEN ir.starttime BETWEEN tp.final_12h_start AND tp.dischtime THEN 'final_12h'
      ELSE NULL
    END AS period
  FROM 
    time_periods tp
  JOIN 
    diagnoses_filter df ON tp.hadm_id = df.hadm_id
  JOIN 
    insulin_regimens ir ON tp.hadm_id = ir.hadm_id
),

regimen_counts AS (
  SELECT 
    medication,
    period,
    COUNT(DISTINCT hadm_id) AS count
  FROM 
    regimen_prevalence
  GROUP BY 
    medication, period
)

-- Calculate final prevalence and percentage-point change
SELECT 
  medication AS regimen,
  COALESCE(first_24h_count / (SELECT total FROM total_patients) * 100, 0) AS first_24h_prevalence,
  COALESCE(final_12h_count / (SELECT total FROM total_patients) * 100, 0) AS final_12h_prevalence,
  COALESCE(final_12h_count / (SELECT total FROM total_patients) * 100, 0) - 
  COALESCE(first_24h_count / (SELECT total FROM total_patients) * 100, 0) AS percentage_point_change
FROM 
  (
    SELECT 
      medication,
      SUM(CASE WHEN period = 'first_24h' THEN count ELSE 0 END) AS first_24h_count,
      SUM(CASE WHEN period = 'final_12h' THEN count ELSE 0 END) AS final_12h_count
    FROM 
      regimen_counts
    GROUP BY 
      medication
  ) AS counts
WHERE 
  medication LIKE '%Basal-Bolus%' OR 
  medication LIKE '%Basal%' OR 
  medication LIKE '%Bolus%' OR 
  medication LIKE '%sliding-scale%';