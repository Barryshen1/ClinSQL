with proper `UNION ALL` for each drug class, combining ACEi/ARB/ARNI into a single "ACEi/ARB/ARNI" class as per clinical guidance.
  2. Use `SUM` and `COUNT` to compute totals and derive percentages.
  3. Add logic to compute continued, initiated, and discontinued flags per patient per drug class.
  4. Ensure all `CASE` expressions are complete and properly parenthesized.
  5. Fix syntax errors: close parentheses, use proper `AS` aliases, and complete the `SELECT` list.

Key changes:
- Complete the `drug_class_union` CTE with full `UNION ALL` for all drug classes.
- Combine ACEi, ARB, and ARNI into a single class in both time windows.
- Add transition logic (continued, initiated, discontinued) per patient per drug class.
- Compute percentages using `SAFE_DIVIDE` to avoid division by zero.

sql
WITH patient_cohort AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 49 AND 59
),
t2dm_condition AS (
  SELECT DISTINCT di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code LIKE 'E11%'
),
hf_condition AS (
  SELECT DISTINCT di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code LIKE 'I50%'
),
eligible_patients AS (
  SELECT p.subject_id
  FROM patient_cohort p
  INNER JOIN t2dm_condition t2 ON p.subject_id = t2.subject_id
  INNER JOIN hf_condition hf ON p.subject_id = hf.subject_id
),
drug_mapping AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    LOWER(p.drug) AS drug_lower,
    p.starttime,
    COALESCE(p.stoptime, a.dischtime) AS stoptime,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a USING (subject_id, hadm_id)
  WHERE p.drug IS NOT NULL
),
classified_drugs AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    -- Antidiabetic
    MAX(CASE
      WHEN drug_lower LIKE '%metformin%' OR drug_lower LIKE '%insulin%' OR
           drug_lower LIKE '%glipizide%' OR drug_lower LIKE '%glyburide%' OR
           drug_lower LIKE '%sitagliptin%' OR drug_lower LIKE '%linagliptin%' OR
           drug_lower LIKE '%empagliflozin%' OR drug_lower LIKE '%dapagliflozin%' OR
           drug_lower LIKE '%liraglutide%' OR drug_lower LIKE '%semaglutide%'
      THEN 1 ELSE 0 END) AS is_antidiabetic,
    -- Beta-Blocker
    MAX(CASE
      WHEN drug_lower LIKE '%metoprolol%' OR drug_lower LIKE '%carvedilol%' OR
           drug_lower LIKE '%bisoprolol%' OR drug_lower LIKE '%atenolol%' OR
           drug_lower LIKE '%nadolol%' OR drug_lower LIKE '%propranolol%'
      THEN 1 ELSE 0 END) AS is_beta_blocker,
    -- ACEi
    MAX(CASE
      WHEN drug_lower LIKE '%lisinopril%' OR drug_lower LIKE '%enalapril%' OR
           drug_lower LIKE '%ramipril%' OR drug_lower LIKE '%captopril%'
      THEN 1 ELSE 0 END) AS is_acei,
    -- ARB
    MAX(CASE
      WHEN drug_lower LIKE '%losartan%' OR drug_lower LIKE '%valsartan%' OR
           drug_lower LIKE '%irbesartan%' OR drug_lower LIKE '%olmesartan%' OR
           drug_lower LIKE '%candesartan%'
      THEN 1 ELSE 0 END) AS is_arb,
    -- ARNI
    MAX(CASE
      WHEN drug_lower LIKE '%sacubitril%' OR drug_lower LIKE '%entresto%'
      THEN 1 ELSE 0 END) AS is_arni,
    -- Loop Diuretic
    MAX(CASE
      WHEN drug_lower LIKE '%furosemide%' OR drug_lower LIKE '%lasix%' OR
           drug_lower LIKE '%bumetanide%' OR drug_lower LIKE '%torsemide%'
      THEN 1 ELSE 0 END) AS is_loop_diuretic
  FROM drug_mapping
  GROUP BY subject_id, hadm_id, admittime, dischtime
),
drug_time_windows AS (
  SELECT
    subject_id,
    -- First 24h: drug started within 24h of admission
    MAX(CASE WHEN starttime <= admittime + INTERVAL '24' HOUR THEN is_antidiabetic ELSE 0 END) AS antidiabetic_first_24h,
    MAX(CASE WHEN starttime <= admittime + INTERVAL '24' HOUR THEN is_beta_blocker ELSE 0 END) AS beta_blocker_first_24h,
    MAX(CASE WHEN starttime <= admittime + INTERVAL '24' HOUR THEN is_acei ELSE 0 END) AS acei_first_24h,
    MAX(CASE WHEN starttime <= admittime + INTERVAL '24' HOUR THEN is_arb ELSE 0 END) AS arb_first_24h,
    MAX(CASE WHEN starttime <= admittime + INTERVAL '24' HOUR THEN is_arni ELSE 0 END) AS arni_first_24h,
    MAX(CASE WHEN starttime <= admittime + INTERVAL '24' HOUR THEN is_loop_diuretic ELSE 0 END) AS loop_diuretic_first_24h,
    -- Final 48h: drug active in last 48h before discharge
    MAX(CASE WHEN stoptime >= dischtime - INTERVAL '48' HOUR AND starttime <= dischtime THEN is_antidiabetic ELSE 0 END) AS antidiabetic_final_48h,
    MAX(CASE WHEN stoptime >= dischtime - INTERVAL '48' HOUR AND starttime <= dischtime THEN is_beta_blocker ELSE 0 END) AS beta_blocker_final_48h,
    MAX(CASE WHEN stoptime >= dischtime - INTERVAL '48' HOUR AND starttime <= dischtime THEN is_acei ELSE 0 END) AS acei_final_48h,
    MAX(CASE WHEN stoptime >= dischtime - INTERVAL '48' HOUR AND starttime <= dischtime THEN is_arb ELSE 0 END) AS arb_final_48h,
    MAX(CASE WHEN stoptime >= dischtime - INTERVAL '48' HOUR AND starttime <= dischtime THEN is_arni ELSE 0 END) AS arni_final_48h,
    MAX(CASE WHEN stoptime >= dischtime - INTERVAL '48' HOUR AND starttime <= dischtime THEN is_loop_diuretic ELSE 0 END) AS loop_diuretic_final_48h
  FROM classified_drugs
  GROUP BY subject_id
),
drug_class_union AS (
  SELECT
    'Antidiabetic' AS drug_class,
    SUM(antidiabetic_first_24h) AS first_24h_count,
    SUM(antidiabetic_final_48h) AS final_48h_count,
    SUM(CASE WHEN antidiabetic_first_24h = 1 AND ant;