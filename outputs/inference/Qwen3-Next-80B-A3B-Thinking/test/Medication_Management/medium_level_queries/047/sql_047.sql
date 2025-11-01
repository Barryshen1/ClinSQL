WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age AS admission_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd 
        ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
      WHERE d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%')
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd 
        ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
      WHERE d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'I50%'
    )
),
medication_classes AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    CASE
      WHEN LOWER(p.drug) LIKE '%sacubitril/valsartan%' THEN 'arni'
      WHEN LOWER(p.drug) LIKE '%lisinopril%' OR LOWER(p.drug) LIKE '%enalapril%' OR LOWER(p.drug) LIKE '%ramipril%' OR LOWER(p.drug) LIKE '%captopril%' OR LOWER(p.drug) LIKE '%quinapril%' OR LOWER(p.drug) LIKE '%benazepril%' OR LOWER(p.drug) LIKE '%perindopril%' OR LOWER(p.drug) LIKE '%trandolapril%' THEN 'acei'
      WHEN LOWER(p.drug) LIKE '%losartan%' OR LOWER(p.drug) LIKE '%valsartan%' OR LOWER(p.drug) LIKE '%irbesartan%' OR LOWER(p.drug) LIKE '%candesartan%' OR LOWER(p.drug) LIKE '%telmisartan%' OR LOWER(p.drug) LIKE '%olmesartan%' OR LOWER(p.drug) LIKE '%azilsartan%' THEN 'arb'
      WHEN LOWER(p.drug) LIKE '%metoprolol%' OR LOWER(p.drug) LIKE '%carvedilol%' OR LOWER(p.drug) LIKE '%atenolol%' OR LOWER(p.drug) LIKE '%propranolol%' OR LOWER(p.drug) LIKE '%bisoprolol%' OR LOWER(p.drug) LIKE '%nadolol%' OR LOWER(p.drug) LIKE '%labetalol%' THEN 'beta-blocker'
      WHEN LOWER(p.drug) LIKE '%insulin%' OR LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' OR LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%dapagliflozin%' THEN 'antidiabetic'
      WHEN LOWER(p.drug) LIKE '%furosemide%' OR LOWER(p.drug) LIKE '%bumetanide%' OR LOWER(p.drug) LIKE '%torsemide%' THEN 'loop_diuretic'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE p.drug IS NOT NULL
),
first_last_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    mc.drug_class,
    MAX(CASE
      WHEN mc.drug_class IS NOT NULL AND (
        (mc.stoptime IS NULL AND mc.starttime <= c.admittime + INTERVAL '24' HOUR) OR
        (mc.stoptime IS NOT NULL AND mc.starttime <= c.admittime + INTERVAL '24' HOUR AND mc.stoptime >= c.admittime)
      ) THEN 1 ELSE 0
    END) AS first_24h_active,
    MAX(CASE
      WHEN mc.drug_class IS NOT NULL AND (
        (mc.stoptime IS NULL AND mc.starttime <= c.dischtime) OR
        (mc.stoptime IS NOT NULL AND mc.starttime <= c.dischtime AND mc.stoptime >= c.dischtime - INTERVAL '24' HOUR)
      ) THEN 1 ELSE 0
    END) AS last_24h_active
  FROM cohort c
  LEFT JOIN medication_classes mc 
    ON c.subject_id = mc.subject_id AND c.hadm_id = mc.hadm_id
  GROUP BY c.subject_id, c.hadm_id, mc.drug_class
)
SELECT
  drug_class,
  COUNT(*) AS total_patients,
  SUM(first_24h_active) AS first_24h_count,
  SUM(last_24h_active) AS last_24h_count,
  SUM(CASE WHEN first_24h_active = 1 AND last_24h_active = 1 THEN 1 ELSE 0 END) AS continued_count,
  SUM(CASE WHEN first_24h_active = 0 AND last_24h_active = 1 THEN 1 ELSE 0 END) AS initiated_late_count,
  SUM(CASE WHEN first_24h_active = 1 AND last_24h_active = 0 THEN 1 ELSE 0 END) AS discontinued_count,
  ROUND(SUM(first_24h_active) * 100.0 / COUNT(*), 2) AS first_24h_percent,
  ROUND(SUM(last_24h_active) * 100.0 / COUNT(*), 2) AS last_24h_percent
FROM first_last_flags
WHERE drug_class IS NOT NULL
GROUP BY drug_class;