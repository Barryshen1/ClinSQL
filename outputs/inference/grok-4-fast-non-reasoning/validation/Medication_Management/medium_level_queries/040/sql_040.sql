WITH cohort AS (
  -- Define cohort: males 36-46 with diabetes + heart failure
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    COUNT(DISTINCT hadm_id) OVER () AS total_admissions
  FROM (
    SELECT DISTINCT 
      ad.subject_id,
      ad.hadm_id,
      ad.admittime,
      ad.dischtime,
      p.gender,
      p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
      ON p.subject_id = ad.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON ad.subject_id = diag.subject_id AND ad.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
      ON diag.icd_code = icd.icd_code AND diag.icd_version = icd.icd_version
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 36 AND 46
      AND EXTRACT(YEAR FROM ad.admittime) = p.anchor_year
      AND (icd.icd_code LIKE 'E1[0-3]%' 
           OR icd.icd_code LIKE 'O24%'  -- Diabetes (incl. gestational)
           OR icd.icd_code LIKE 'I50.%')  -- Heart failure
      AND ad.hospital_expire_flag = 0  -- Inpatient, non-expired (per question)
      AND TIMESTAMP_DIFF(TIMESTAMP(ad.dischtime), TIMESTAMP(ad.admittime), HOUR) >= 48  -- Ensure valid last 12h
  )
  GROUP BY subject_id, hadm_id, admittime, dischtime
  HAVING SUM(CASE WHEN icd.icd_code LIKE 'E1[0-3]%' OR icd.icd_code LIKE 'O24%' THEN 1 ELSE 0 END) > 0  -- Has diabetes
     AND SUM(CASE WHEN icd.icd_code LIKE 'I50.%' THEN 1 ELSE 0 END) > 0  -- Has HF
),

drug_orders AS (
  -- All relevant prescriptions for cohort
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.total_admissions,
    pr.drug,
    pr.starttime
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
),

time_windows AS (
  -- Classify orders into windows per admission
  SELECT 
    do.*,
    CASE 
      WHEN TIMESTAMP(do.starttime) >= TIMESTAMP(do.admittime) 
           AND TIMESTAMP(do.starttime) < TIMESTAMP_ADD(TIMESTAMP(do.admittime), INTERVAL 48 HOUR)
      THEN 'first48' 
      WHEN TIMESTAMP(do.starttime) >= TIMESTAMP_SUB(TIMESTAMP(do.dischtime), INTERVAL 12 HOUR)
           AND TIMESTAMP(do.starttime) <= TIMESTAMP(do.dischtime)
      THEN 'last12'
    END AS window
  FROM drug_orders do
  WHERE TIMESTAMP(do.starttime) >= TIMESTAMP(do.admittime)  -- Orders after admission
),

classified_drugs AS (
  -- Assign classes (antidiabetic and cardiac)
  SELECT 
    tw.hadm_id,
    tw.window,
    tw.total_admissions,
    CASE 
      -- Antidiabetic
      WHEN LOWER(tw.drug) LIKE '%metformin%' THEN 'Antidiabetic: Biguanides'
      WHEN LOWER(tw.drug) IN ('glipizide', 'glyburide', 'glimepiride', 'tolbutamide') 
           OR LOWER(tw.drug) LIKE '%sulfonylurea%' THEN 'Antidiabetic: Sulfonylureas'
      WHEN LOWER(tw.drug) LIKE '%sitagliptin%' OR LOWER(tw.drug) LIKE '%linagliptin%' 
           OR LOWER(tw.drug) LIKE '%saxagliptin%' OR LOWER(tw.drug) LIKE '%alogliptin%' THEN 'Antidiabetic: DPP-4 Inhibitors'
      WHEN LOWER(tw.drug) LIKE '%dapagliflozin%' OR LOWER(tw.drug) LIKE '%empagliflozin%' 
           OR LOWER(tw.drug) LIKE '%canagliflozin%' OR LOWER(tw.drug) LIKE '%ertugliflozin%' THEN 'Antidiabetic: SGLT2 Inhibitors'
      WHEN LOWER(tw.drug) LIKE '%insulin%' THEN 'Antidiabetic: Insulin'
      -- Cardiac (HF-focused)
      WHEN LOWER(tw.drug) LIKE '%metoprolol%' OR LOWER(tw.drug) LIKE '%carvedilol%' 
           OR LOWER(tw.drug) LIKE '%bisoprolol%' OR LOWER(tw.drug) LIKE '%atenolol%' THEN 'Cardiac: Beta-blockers'
      WHEN LOWER(tw.drug) LIKE '%lisinopril%' OR LOWER(tw.drug) LIKE '%ramipril%' OR LOWER(tw.drug) LIKE '%enalapril%'
           OR LOWER(tw.drug) LIKE '%losartan%' OR LOWER(tw.drug) LIKE '%valsartan%' THEN 'Cardiac: ACEi/ARBs'
      WHEN LOWER(tw.drug) LIKE '%furosemide%' OR LOWER(tw.drug) LIKE '%bumetanide%' OR LOWER(tw.drug) LIKE '%torsemide%'
           OR LOWER(tw.drug) LIKE '%spironolactone%' OR LOWER(tw.drug) LIKE '%eplerenone%' THEN 'Cardiac: Diuretics'
      ELSE NULL
    END AS drug_class
  FROM time_windows tw
  WHERE tw.window IS NOT NULL
)

-- Aggregate prevalence (%) and differences
SELECT 
  drug_class,
  ROUND((SUM(CASE WHEN window = 'first48' THEN 1 ELSE 0 END) * 100.0 / total_admissions), 2) AS first48_prevalence_pct,
  ROUND((SUM(CASE WHEN window = 'last12' THEN 1 ELSE 0 END) * 100.0 / total_admissions), 2) AS last12_prevalence_pct,
  ROUND(
    (SUM(CASE WHEN window = 'first48' THEN 1 ELSE 0 END) * 100.0 / total_admissions) -
    (SUM(CASE WHEN window = 'last12' THEN 1 ELSE 0 END) * 100.0 / total_admissions), 2
  ) AS abs_diff_pp
FROM classified_drugs
WHERE drug_class IS NOT NULL
GROUP BY drug_class, total_admissions
ORDER BY 
  CASE drug_class 
    WHEN 'Antidiabetic: Biguanides' THEN 1
    WHEN 'Antidiabetic: Sulfonylureas' THEN 2
    WHEN 'Antidiabetic: DPP-4 Inhibitors' THEN 3
    WHEN 'Antidiabetic: SGLT2 Inhibitors' THEN 4
    WHEN 'Antidiabetic: Insulin' THEN 5
    WHEN 'Cardiac: Beta-blockers' THEN 6
    WHEN 'Cardiac: ACEi/ARBs' THEN 7
    WHEN 'Cardiac: Diuretics' THEN 8
  END;