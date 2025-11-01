WITH cohort AS (
  -- Define cohort: males 40-50 with both diabetes and heart failure (any diagnosis position)
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND (
      -- Diabetes (ICD-10 and ICD-9)
      (d.icd_version = 10 AND (d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR d.icd_code LIKE 'E10%' OR 
                                 d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%'))
      OR
      (d.icd_version = 9 AND d.icd_code LIKE '250.%')
    )
    AND (
      -- Heart failure (ICD-10 and ICD-9)
      (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
      OR
      (d.icd_version = 9 AND d.icd_code LIKE '428.%')
    )
),

med_orders AS (
  -- Get medication orders overlapping admission
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    c.admittime, 
    c.dischtime,
    pr.starttime,
    pr.stoptime,
    CASE 
      WHEN LOWER(pr.drug) LIKE '%insulin%' OR LOWER(pr.drug) LIKE '%metformin%' OR 
           LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%sulfonylurea%' OR 
           LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%dpp-4%' OR 
           LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%glp-1%' OR 
           LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%sglt2%'
      THEN 'Antidiabetic'
      WHEN LOWER(pr.drug) LIKE '%beta blocker%' OR LOWER(pr.drug) LIKE '%metoprolol%' OR 
           LOWER(pr.drug) LIKE '%atenolol%' OR LOWER(pr.drug) LIKE '%carvedilol%' OR 
           LOWER(pr.drug) LIKE '%bisoprolol%' OR LOWER(pr.drug) LIKE '%propranolol%'
      THEN 'Beta-blocker'
      WHEN LOWER(pr.drug) LIKE '%ace inhibitor%' OR LOWER(pr.drug) LIKE '%lisinopril%' OR LOWER(pr.drug) LIKE '%enalapril%' OR
           LOWER(pr.drug) LIKE '%losartan%' OR LOWER(pr.drug) LIKE '%valsartan%' OR LOWER(pr.drug) LIKE '%candesartan%' OR
           LOWER(pr.drug) LIKE '%sacubitril%' OR LOWER(pr.drug) LIKE '%entresto%' OR LOWER(pr.drug) LIKE '%ar ni%'
      THEN 'ACEi/ARB/ARNI'
      WHEN LOWER(pr.drug) LIKE '%furosemide%' OR LOWER(pr.drug) LIKE '%bumetanide%' OR 
           LOWER(pr.drug) LIKE '%torsemide%' AND LOWER(pr.drug) NOT LIKE '%spironolactone%'
      THEN 'Loop diuretic'
    END AS med_category
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= c.admittime 
    AND (pr.stoptime <= c.dischtime OR pr.stoptime IS NULL)
    AND pr.starttime < c.dischtime  -- Ensure order starts before discharge
    AND med_category IS NOT NULL  -- Only relevant categories
),

admission_meds AS (
  -- One row per admission per category (active if any order)
  SELECT 
    subject_id, 
    hadm_id, 
    med_category,
    admittime, 
    dischtime,
    -- Active in first 24h: any order starts <= first 24h
    LOGICAL_OR(starttime <= TIMESTAMP_ADD(admittime, INTERVAL 24 HOUR)) AS active_first_24h,
    -- Active in last 24h: any order ends >= last 24h or NULL (and starts before discharge)
    LOGICAL_OR(
      (stoptime >= TIMESTAMP_SUB(dischtime, INTERVAL 24 HOUR) OR stoptime IS NULL) 
      AND starttime <= dischtime
    ) AS active_last_24h
  FROM med_orders
  GROUP BY subject_id, hadm_id, med_category, admittime, dischtime
)

-- Summary metrics
SELECT 
  med_category,
  COUNT(DISTINCT CONCAT(subject_id, '_', hadm_id)) AS total_admissions,
  COUNT(DISTINCT subject_id) AS total_patients,
  ROUND(AVG(CAST(active_first_24h AS FLOAT64)) * 100, 2) AS pct_on_first_24h,
  ROUND(AVG(CAST(active_last_24h AS FLOAT64)) * 100, 2) AS pct_on_last_24h,
  SUM(CAST((active_first_24h AND active_last_24h) AS INT64)) AS count_continued,
  SUM(CAST((active_last_24h AND NOT active_first_24h) AS INT64)) AS count_initiated_late,
  SUM(CAST((active_first_24h AND NOT active_last_24h) AS INT64)) AS count_discontinued
FROM admission_meds
GROUP BY med_category
ORDER BY 
  CASE med_category 
    WHEN 'Antidiabetic' THEN 1
    WHEN 'Beta-blocker' THEN 2
    WHEN 'ACEi/ARB/ARNI' THEN 3
    WHEN 'Loop diuretic' THEN 4
  END;