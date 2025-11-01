WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (p.anchor_year - EXTRACT(YEAR FROM a.admittime)) BETWEEN 77 AND 87
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          d.icd_code LIKE 'E08%' OR
          d.icd_code LIKE 'E09%' OR
          d.icd_code LIKE 'E10%' OR
          d.icd_code LIKE 'E11%' OR
          d.icd_code LIKE 'E13%' OR
          d.icd_code LIKE 'E14%'
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'I50%'
    )
),

drug_classes AS (
  SELECT 
    hadm_id,
    drug,
    starttime,
    -- Antidiabetics
    CASE WHEN 
      LOWER(drug) LIKE '%insulin%' OR
      LOWER(drug) LIKE '%metformin%' OR
      LOWER(drug) LIKE '%glipizide%' OR
      LOWER(drug) LIKE '%glimepiride%' OR
      LOWER(drug) LIKE '%glyburide%' OR
      LOWER(drug) LIKE '%sitagliptin%' OR
      LOWER(drug) LIKE '%exenatide%' OR
      LOWER(drug) LIKE '%liraglutide%' OR
      LOWER(drug) LIKE '%dapagliflozin%' OR
      LOWER(drug) LIKE '%empagliflozin%' OR
      LOWER(drug) LIKE '%canagliflozin%' OR
      LOWER(drug) LIKE '%pioglitazone%' OR
      LOWER(drug) LIKE '%rosiglitazone%' OR
      LOWER(drug) LIKE '%acarbose%' OR
      LOWER(drug) LIKE '%miglitol%' OR
      LOWER(drug) LIKE '%repaglinide%' OR
      LOWER(drug) LIKE '%nateglinide%'
      THEN 1 ELSE 0 END AS antidiabetic,
    -- Beta-blockers
    CASE WHEN 
      LOWER(drug) LIKE '%metoprolol%' OR
      LOWER(drug) LIKE '%carvedilol%' OR
      LOWER(drug) LIKE '%bisoprolol%' OR
      LOWER(drug) LIKE '%atenolol%' OR
      LOWER(drug) LIKE '%propranolol%' OR
      LOWER(drug) LIKE '%nadolol%' OR
      LOWER(drug) LIKE '%timolol%' OR
      LOWER(drug) LIKE '%labetalol%'
      THEN 1 ELSE 0 END AS beta_blocker,
    -- ACEi/ARB/ARNI
    CASE WHEN 
      LOWER(drug) LIKE '%lisinopril%' OR
      LOWER(drug) LIKE '%enalapril%' OR
      LOWER(drug) LIKE '%ramipril%' OR
      LOWER(drug) LIKE '%captopril%' OR
      LOWER(drug) LIKE '%losartan%' OR
      LOWER(drug) LIKE '%valsartan%' OR
      LOWER(drug) LIKE '%irbesartan%' OR
      LOWER(drug) LIKE '%candesartan%' OR
      LOWER(drug) LIKE '%sacubitril%'
      THEN 1 ELSE 0 END AS ace_arni_arb,
    -- Loop diuretics
    CASE WHEN 
      LOWER(drug) LIKE '%furosemide%' OR
      LOWER(drug) LIKE '%bumetanide%' OR
      LOWER(drug) LIKE '%torsemide%' OR
      LOWER(drug) LIKE '%ethacrynic%'
      THEN 1 ELSE 0 END AS loop_diuretic
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
),

first_administration AS (
  SELECT 
    c.hadm_id,
    MIN(CASE WHEN dc.antidiabetic = 1 THEN dc.starttime ELSE NULL END) AS first_antidiabetic,
    MIN(CASE WHEN dc.beta_blocker = 1 THEN dc.starttime ELSE NULL END) AS first_beta_blocker,
    MIN(CASE WHEN dc.ace_arni_arb = 1 THEN dc.starttime ELSE NULL END) AS first_ace_arni_arb,
    MIN(CASE WHEN dc.loop_diuretic = 1 THEN dc.starttime ELSE NULL END) AS first_loop_diuretic,
    c.admittime,
    c.dischtime
  FROM cohort c
  LEFT JOIN drug_classes dc ON c.hadm_id = dc.hadm_id
  GROUP BY c.hadm_id, c.admittime, c.dischtime
),

time_windows AS (
  SELECT 
    hadm_id,
    -- First 48 hours
    CASE WHEN first_antidiabetic IS NOT NULL AND 
              DATETIME_DIFF(first_antidiabetic, admittime, HOUR) <= 48 
         THEN 1 ELSE 0 END AS antidiabetic_first_48h,
    CASE WHEN first_beta_blocker IS NOT NULL AND 
              DATETIME_DIFF(first_beta_blocker, admittime, HOUR) <= 48 
         THEN 1 ELSE 0 END AS beta_blocker_first_48h,
    CASE WHEN first_ace_arni_arb IS NOT NULL AND 
              DATETIME_DIFF(first_ace_arni_arb, admittime, HOUR) <= 48 
         THEN 1 ELSE 0 END AS ace_arni_arb_first_48h,
    CASE WHEN first_loop_diuretic IS NOT NULL AND 
              DATETIME_DIFF(first_loop_diuretic, admittime, HOUR) <= 48 
         THEN 1 ELSE 0 END AS loop_diuretic_first_48h,
    -- Last 12 hours
    CASE WHEN first_antidiabetic IS NOT NULL AND 
              DATETIME_DIFF(dischtime, first_antidiabetic, HOUR) <= 12 
         THEN 1 ELSE 0 END AS antidiabetic_last_12h,
    CASE WHEN first_beta_blocker IS NOT NULL AND 
              DATETIME_DIFF(dischtime, first_beta_blocker, HOUR) <= 12 
         THEN 1 ELSE 0 END AS beta_blocker_last_12h,
    CASE WHEN first_ace_arni_arb IS NOT NULL AND 
              DATETIME_DIFF(dischtime, first_ace_arni_arb, HOUR) <= 12 
         THEN 1 ELSE 0 END AS ace_arni_arb_last_12h,
    CASE WHEN first_loop_diuretic IS NOT NULL AND 
              DATETIME_DIFF(dischtime, first_loop_diuretic, HOUR) <= 12 
         THEN 1 ELSE 0 END AS loop_diuretic_last_12h
  FROM first_administration
)

SELECT 
  'Antidiabetics' AS drug_class,
  AVG(antidiabetic_first_48h) * 100 AS first_48h_rate,
  AVG(antidiabetic_last_12h) * 100 AS last_12h_rate,
  (AVG(antidiabetic_last_12h) - AVG(antidiabetic_first_48h)) * 100 AS net_change
FROM time_windows
UNION ALL
SELECT 
  'Beta-blockers' AS drug_class,
  AVG(beta_blocker_first_48h) * 100 AS first_48h_rate,
  AVG(beta_blocker_last_12h) * 100 AS last_12h_rate,
  (AVG(beta_blocker_last_12h) - AVG(beta_blocker_first_48h)) * 100 AS net_change
FROM time_windows
UNION ALL
SELECT 
  'ACEi/ARB/ARNI' AS drug_class,
  AVG(ace_arni_arb_first_48h) * 100 AS first_48h_rate,
  AVG(ace_arni_arb_last_12h) * 100 AS last_12h_rate,
  (AVG(ace_arni_arb_last_12h) - AVG(ace_arni_arb_first_48h)) * 100 AS net_change
FROM time_windows
UNION ALL
SELECT 
  'Loop diuretics' AS drug_class,
  AVG(loop_diuretic_first_48h) * 100 AS first_48h_rate,
  AVG(loop_diuretic_last_12h) * 100 AS last_12h_rate,
  (AVG(loop_diuretic_last_12h) - AVG(loop_diuretic_first_48h)) * 100 AS net_change
FROM time_windows;