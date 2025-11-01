WITH cohort AS (
  -- Select male patients aged 36-46
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
),

admissions_with_dx AS (
  -- Join admissions and diagnoses for T2DM + HF
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN cohort c ON a.subject_id = c.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE a.hospital_expire_flag = 0  -- Alive at discharge
    AND (
      -- T2DM: ICD-9 250.00-250.93 (excl. type 1), ICD-10 E11.*
      (d.icd_version = '9' AND d.icd_code LIKE '250.%' AND d.icd_code NOT LIKE '250.1%' AND d.icd_code NOT LIKE '250.x1')
      OR (d.icd_version = '10' AND d.icd_code LIKE 'E11%')
    )
    AND (
      -- Heart failure: ICD-9 425.4-425.9, 428.*; ICD-10 I50.*, I11.0, I13.0/2
      (d.icd_version = '9' AND (d.icd_code LIKE '425[4-9]%' OR d.icd_code LIKE '428%'))
      OR (d.icd_version = '10' AND (d.icd_code LIKE 'I50%' OR d.icd_code IN ('I11.0', 'I13.0', 'I13.2')))
    )
),

total_admissions AS (
  SELECT COUNT(*) AS total_count
  FROM admissions_with_dx
),

initiations AS (
  -- Find initiations in windows (restructured to avoid parsing error)
  SELECT 
    awd.hadm_id,
    awd.subject_id,
    CASE 
      WHEN pr.drug LIKE '%metformin%' THEN 'Biguanides'
      WHEN pr.drug LIKE '%glipizide%' OR pr.drug LIKE '%glyburide%' OR pr.drug LIKE '%glimepiride%' OR pr.drug LIKE '%gliclazide%' OR pr.drug LIKE '%sulfonylurea%' THEN 'Sulfonylureas'
      WHEN pr.drug LIKE '%sitagliptin%' OR pr.drug LIKE '%saxagliptin%' OR pr.drug LIKE '%linagliptin%' OR pr.drug LIKE '%alogliptin%' THEN 'DPP-4 Inhibitors'
      WHEN pr.drug LIKE '%empagliflozin%' OR pr.drug LIKE '%dapagliflozin%' OR pr.drug LIKE '%canagliflozin%' THEN 'SGLT2 Inhibitors'
      WHEN pr.drug LIKE '%insulin%' THEN 'Insulin'
      ELSE 'Other'
    END AS drug_class,
    CASE 
      WHEN pr.starttime >= awd.admittime AND pr.starttime < TIMESTAMP_ADD(awd.admittime, INTERVAL 12 HOUR) THEN 'first_12h'
      WHEN pr.starttime >= TIMESTAMP_SUB(awd.dischtime, INTERVAL 48 HOUR) AND pr.starttime < awd.dischtime THEN 'final_48h'
      ELSE NULL
    END AS window
  FROM admissions_with_dx awd
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON awd.subject_id = pr.subject_id AND awd.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND window IS NOT NULL  -- Filter to only relevant windows after assignment
    AND (
      pr.drug LIKE '%metformin%' OR
      (pr.drug LIKE '%glipizide%' OR pr.drug LIKE '%glyburide%' OR pr.drug LIKE '%glimepiride%' OR pr.drug LIKE '%gliclazide%' OR pr.drug LIKE '%sulfonylurea%') OR
      (pr.drug LIKE '%sitagliptin%' OR pr.drug LIKE '%saxagliptin%' OR pr.drug LIKE '%linagliptin%' OR pr.drug LIKE '%alogliptin%') OR
      (pr.drug LIKE '%empagliflozin%' OR pr.drug LIKE '%dapagliflozin%' OR pr.drug LIKE '%canagliflozin%') OR
      pr.drug LIKE '%insulin%'
    )
),

initiation_counts AS (
  -- Count unique hadm_id per class and window
  SELECT 
    drug_class,
    window,
    COUNT(DISTINCT hadm_id) AS init_count
  FROM initiations
  GROUP BY drug_class, window
),

rates AS (
  -- Compute rates
  SELECT 
    drug_class,
    COALESCE(SUM(CASE WHEN window = 'first_12h' THEN init_count ELSE 0 END), 0) / MAX(ta.total_count) * 100 AS first_12h_rate,
    COALESCE(SUM(CASE WHEN window = 'final_48h' THEN init_count ELSE 0 END), 0) / MAX(ta.total_count) * 100 AS final_48h_rate,
    (COALESCE(SUM(CASE WHEN window = 'final_48h' THEN init_count ELSE 0 END), 0) - 
     COALESCE(SUM(CASE WHEN window = 'first_12h' THEN init_count ELSE 0 END), 0)) / MAX(ta.total_count) * 100 AS net_change_pp
  FROM initiation_counts
  CROSS JOIN total_admissions ta
  GROUP BY drug_class
)

SELECT 
  drug_class,
  ROUND(first_12h_rate, 2) AS first_12h_rate_pct,
  ROUND(final_48h_rate, 2) AS final_48h_rate_pct,
  ROUND(net_change_pp, 2) AS net_change_pp
FROM rates
WHERE drug_class != 'Other'  -- Exclude uncategorized
ORDER BY net_change_pp DESC;