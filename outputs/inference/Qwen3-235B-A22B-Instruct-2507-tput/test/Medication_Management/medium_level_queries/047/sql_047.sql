WITH patients_filtered AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 40 AND 50
),
admissions_with_conditions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_filtered pf ON a.subject_id = pf.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY a.hadm_id, a.admittime, a.dischtime
  HAVING 
    SUM(CASE WHEN LOWER(d.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) > 0
    AND SUM(CASE WHEN LOWER(d.long_title) LIKE '%heart failure%' OR LOWER(d.long_title) LIKE '%hf%' THEN 1 ELSE 0 END) > 0
),
drug_exposure AS (
  SELECT 
    a.hadm_id,
    -- Antidiabetic
    MAX(CASE 
      WHEN LOWER(p.drug) LIKE '%insulin%' 
        OR LOWER(p.drug) LIKE '%metformin%'
        OR LOWER(p.drug) LIKE '%glipizide%'
        OR LOWER(p.drug) LIKE '%glimepiride%'
        OR LOWER(p.drug) LIKE '%sitagliptin%'
        OR LOWER(p.drug) LIKE '%liraglutide%'
        OR LOWER(p.drug) LIKE '%dapa%' 
        OR LOWER(p.drug) LIKE '%empa%'
        OR LOWER(p.drug) LIKE '%canagliflozin%'
        OR LOWER(p.drug) LIKE '%pioglitazone%'
        OR LOWER(p.drug) LIKE '%rosiglitazone%'
        OR LOWER(p.drug) LIKE '%acarbose%'
        OR LOWER(p.drug) LIKE '%repaglinide%'
        THEN 1 ELSE 0 END) AS antidiabetic_any,
    -- Beta-blocker
    MAX(CASE 
      WHEN LOWER(p.drug) LIKE '%metoprolol%'
        OR LOWER(p.drug) LIKE '%carvedilol%'
        OR LOWER(p.drug) LIKE '%bisoprolol%'
        OR LOWER(p.drug) LIKE '%atenolol%'
        OR LOWER(p.drug) LIKE '%nadolol%'
        OR LOWER(p.drug) LIKE '%propranolol%'
        OR LOWER(p.drug) LIKE '%labetalol%'
        OR LOWER(p.drug) LIKE '%nebivolol%'
        THEN 1 ELSE 0 END) AS beta_blocker_any,
    -- ACEi/ARB/ARNI
    MAX(CASE 
      WHEN LOWER(p.drug) LIKE '%lisinopril%'
        OR LOWER(p.drug) LIKE '%enalapril%'
        OR LOWER(p.drug) LIKE '%ramipril%'
        OR LOWER(p.drug) LIKE '%benazepril%'
        OR LOWER(p.drug) LIKE '%quinapril%'
        OR LOWER(p.drug) LIKE '%perindopril%'
        OR LOWER(p.drug) LIKE '%trandolapril%'
        OR LOWER(p.drug) LIKE '%captopril%'
        OR LOWER(p.drug) LIKE '%fosinopril%'
        OR LOWER(p.drug) LIKE '%losartan%'
        OR LOWER(p.drug) LIKE '%valsartan%'
        OR LOWER(p.drug) LIKE '%irbesartan%'
        OR LOWER(p.drug) LIKE '%candesartan%'
        OR LOWER(p.drug) LIKE '%telmisartan%'
        OR LOWER(p.drug) LIKE '%olmesartan%'
        OR LOWER(p.drug) LIKE '%azilsartan%'
        OR LOWER(p.drug) LIKE '%sacubitril%'
        THEN 1 ELSE 0 END) AS acei_arb_arni_any,
    -- Loop diuretic
    MAX(CASE 
      WHEN LOWER(p.drug) LIKE '%furosemide%'
        OR LOWER(p.drug) LIKE '%bumetanide%'
        OR LOWER(p.drug) LIKE '%torsemide%'
        THEN 1 ELSE 0 END) AS loop_diuretic_any
  FROM admissions_with_conditions a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions p
    ON a.hadm_id = p.hadm_id
  GROUP BY a.hadm_id
)
SELECT
  'Antidiabetic' AS drug_class,
  SUM(antidiabetic_any) AS total_exposed,
  ROUND(100 * AVG(CAST(antidiabetic_any AS FLOAT64)), 2) AS percent_exposed
FROM drug_exposure
UNION ALL
SELECT
  'Beta-blocker' AS drug_class,
  SUM(beta_blocker_any) AS total_exposed,
  ROUND(100 * AVG(CAST(beta_blocker_any AS FLOAT64)), 2) AS percent_exposed
FROM drug_exposure
UNION ALL
SELECT
  'ACEi/ARB/ARNI' AS drug_class,
  SUM(acei_arb_arni_any) AS total_exposed,
  ROUND(100 * AVG(CAST(acei_arb_arni_any AS FLOAT64)), 2) AS percent_exposed
FROM drug_exposure
UNION ALL
SELECT
  'Loop diuretic' AS drug_class,
  SUM(loop_diuretic_any) AS total_exposed,
  ROUND(100 * AVG(CAST(loop_diuretic_any AS FLOAT64)), 2) AS percent_exposed
FROM drug_exposure
ORDER BY drug_class;