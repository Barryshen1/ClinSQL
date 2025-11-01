WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    -- Calculate age at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 36 AND 46
    -- Diabetes diagnosis (ICD-9/10)
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'E08%' 
              OR d.icd_code LIKE 'E09%' 
              OR d.icd_code LIKE 'E10%' 
              OR d.icd_code LIKE 'E11%' 
              OR d.icd_code LIKE 'E13%')
        )
    )
    -- Heart failure diagnosis (ICD-9/10)
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),
class_definitions AS (
  -- Antidiabetic classes
  SELECT 'Antidiabetic - Biguanides' AS drug_class, 'metformin' AS drug_pattern
  UNION ALL SELECT 'Antidiabetic - Sulfonylureas', 'glipizide'
  UNION ALL SELECT 'Antidiabetic - Sulfonylureas', 'glyburide'
  UNION ALL SELECT 'Antidiabetic - Sulfonylureas', 'glimepiride'
  UNION ALL SELECT 'Antidiabetic - DPP4 inhibitors', 'sitagliptin'
  UNION ALL SELECT 'Antidiabetic - DPP4 inhibitors', 'saxagliptin'
  UNION ALL SELECT 'Antidiabetic - DPP4 inhibitors', 'linagliptin'
  UNION ALL SELECT 'Antidiabetic - DPP4 inhibitors', 'alogliptin'
  UNION ALL SELECT 'Antidiabetic - SGLT2 inhibitors', 'empagliflozin'
  UNION ALL SELECT 'Antidiabetic - SGLT2 inhibitors', 'dapagliflozin'
  UNION ALL SELECT 'Antidiabetic - SGLT2 inhibitors', 'canagliflozin'
  UNION ALL SELECT 'Antidiabetic - SGLT2 inhibitors', 'ertugliflozin'
  UNION ALL SELECT 'Antidiabetic - Insulins', 'insulin'
  -- Cardiac classes
  UNION ALL SELECT 'Cardiac - ACE inhibitors', 'lisinopril'
  UNION ALL SELECT 'Cardiac - ACE inhibitors', 'enalapril'
  UNION ALL SELECT 'Cardiac - ACE inhibitors', 'ramipril'
  UNION ALL SELECT 'Cardiac - ACE inhibitors', 'benazepril'
  UNION ALL SELECT 'Cardiac - ACE inhibitors', 'captopril'
  UNION ALL SELECT 'Cardiac - ACE inhibitors', 'fosinopril'
  UNION ALL SELECT 'Cardiac - ACE inhibitors', 'moexipril'
  UNION ALL SELECT 'Cardiac - ACE inhibitors', 'perindopril'
  UNION ALL SELECT 'Cardiac - ACE inhibitors', 'quinapril'
  UNION ALL SELECT 'Cardiac - ACE inhibitors', 'trandolapril'
  UNION ALL SELECT 'Cardiac - ARBs', 'losartan'
  UNION ALL SELECT 'Cardiac - ARBs', 'valsartan'
  UNION ALL SELECT 'Cardiac - ARBs', 'irbesartan'
  UNION ALL SELECT 'Cardiac - ARBs', 'candesartan'
  UNION ALL SELECT 'Cardiac - ARBs', 'olmesartan'
  UNION ALL SELECT 'Cardiac - ARBs', 'telmisartan'
  UNION ALL SELECT 'Cardiac - ARBs', 'azilsartan'
  UNION ALL SELECT 'Cardiac - Beta-blockers', 'metoprolol'
  UNION ALL SELECT 'Cardiac - Beta-blockers', 'carvedilol'
  UNION ALL SELECT 'Cardiac - Beta-blockers', 'bisoprolol'
  UNION ALL SELECT 'Cardiac - Beta-blockers', 'nebivolol'
  UNION ALL SELECT 'Cardiac - Diuretics', 'furosemide'
  UNION ALL SELECT 'Cardiac - Diuretics', 'bumetanide'
  UNION ALL SELECT 'Cardiac - Diuretics', 'torsemide'
  UNION ALL SELECT 'Cardiac - Diuretics', 'hydrochlorothiazide'
  UNION ALL SELECT 'Cardiac - Diuretics', 'chlorthalidone'
  UNION ALL SELECT 'Cardiac - Diuretics', 'metolazone'
  UNION ALL SELECT 'Cardiac - Aldosterone antagonists', 'spironolactone'
  UNION ALL SELECT 'Cardiac - Aldosterone antagonists', 'eplerenone'
  UNION ALL SELECT 'Cardiac - SGLT2 inhibitors', 'dapagliflozin'
  UNION ALL SELECT 'Cardiac - SGLT2 inhibitors', 'empagliflozin'
),
class_admission AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    cd.drug_class
  FROM cohort c
  CROSS JOIN class_definitions cd
),
drug_class_flags AS (
  SELECT 
    ca.subject_id,
    ca.hadm_id,
    ca.drug_class,
    MAX(CASE WHEN 
          p.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR) 
          AND (p.stoptime >= c.admittime OR p.stoptime IS NULL)
        THEN 1 ELSE 0 END) AS in_first_48h,
    MAX(CASE WHEN 
          p.starttime <= c.dischtime 
          AND (p.stoptime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) OR p.stoptime IS NULL)
        THEN 1 ELSE 0 END) AS in_last_12h
  FROM class_admission ca
  INNER JOIN cohort c 
    ON ca.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  LEFT JOIN class_definitions cd
    ON ca.drug_class = cd.drug_class
    AND LOWER(p.drug) LIKE CONCAT('%', cd.drug_pattern, '%')
  GROUP BY ca.subject_id, ca.hadm_id, ca.drug_class
)
SELECT 
  drug_class,
  SUM(in_first_48h) * 100.0 / (SELECT COUNT(*) FROM cohort) AS prevalence_first_48h,
  SUM(in_last_12h) * 100.0 / (SELECT COUNT(*) FROM cohort) AS prevalence_last_12h,
  (SUM(in_first_48h) * 100.0 / (SELECT COUNT(*) FROM cohort) 
   - SUM(in_last_12h) * 100.0 / (SELECT COUNT(*) FROM cohort)) AS absolute_difference
FROM drug_class_flags
GROUP BY drug_class
ORDER BY drug_class;