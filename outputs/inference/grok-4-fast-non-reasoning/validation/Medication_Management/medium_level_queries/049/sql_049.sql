WITH cohort AS (
  -- Identify admissions with diabetes and heart failure
  WITH diagnoses AS (
    SELECT 
      di.subject_id,
      di.hadm_id,
      STRING_AGG(dd.long_title, '; ') AS diag_titles
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    GROUP BY di.subject_id, di.hadm_id
  )
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN diagnoses d ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND (d.diag_titles LIKE '%diabetes%' OR d.diag_titles LIKE '%E08%' OR d.diag_titles LIKE '%E09%' OR d.diag_titles LIKE '%E10%' OR d.diag_titles LIKE '%E11%' OR d.diag_titles LIKE '%E13%')
    AND (d.diag_titles LIKE '%heart failure%' OR d.diag_titles LIKE '%I50%')
    AND DATE_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),

antidiabetics AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    pr.drug,
    pr.starttime,
    CASE 
      WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'Insulins'
      WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'Biguanides'
      WHEN LOWER(pr.drug) IN ('GLIPIZIDE', 'GLYBURIDE', 'GLIMEPIRIDE') OR LOWER(pr.drug) LIKE '%sulfonylurea%' THEN 'Sulfonylureas'
      WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' THEN 'DPP-4 Inhibitors'
      WHEN LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%canagliflozin%' THEN 'SGLT2 Inhibitors'
      WHEN LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%semaglutide%' OR LOWER(pr.drug) LIKE '%exenatide%' THEN 'GLP-1 Agonists'
      WHEN LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinediones'
      ELSE 'Other Antidiabetics'
    END AS antidiabetic_class
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.drug IS NOT NULL
    AND (
      LOWER(pr.drug) LIKE '%insulin%' OR
      LOWER(pr.drug) LIKE '%metformin%' OR
      LOWER(pr.drug) IN ('GLIPIZIDE', 'GLYBURIDE', 'GLIMEPIRIDE', 'SITAGLIPTIN', 'LINAGLIPTIN', 'SAXAGLIPTIN', 'EMPAGLIFLOZIN', 'DAPAGLIFLOZIN', 'CANAGLIFLOZIN', 'LIRAGLUTIDE', 'SEMAGLUTIDE', 'EXENATIDE', 'PIOGLITAZONE', 'ROSIGLITAZONE')
    )
),

time_periods AS (
  SELECT 
    hadm_id,
    antidiabetic_class,
    admittime,
    dischtime,
    starttime,
    'first_72h' AS time_period
  FROM antidiabetics
  WHERE starttime >= admittime 
    AND starttime < TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR)

  UNION ALL

  SELECT 
    hadm_id,
    antidiabetic_class,
    admittime,
    dischtime,
    starttime,
    'final_24h' AS time_period
  FROM antidiabetics
  WHERE starttime >= TIMESTAMP_SUB(dischtime, INTERVAL 24 HOUR)
    AND starttime < dischtime
)

SELECT 
  tp.time_period,
  tp.antidiabetic_class,
  ROUND(100.0 * COUNT(DISTINCT tp.hadm_id) / COUNT(DISTINCT c.hadm_id), 1) AS percentage
FROM time_periods tp
CROSS JOIN cohort c  -- For total cohort denominator per window (assumes same total for both)
WHERE tp.hadm_id = c.hadm_id  -- Align to cohort
GROUP BY tp.time_period, tp.antidiabetic_class
HAVING percentage > 0  -- Optional: hide 0% classes
ORDER BY tp.time_period, percentage DESC;