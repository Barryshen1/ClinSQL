with a comma, which is invalid. This suggests the CTE (`WITH` clause) was not properly initiated. However, in the provided partial query, the `WITH` keyword is present, so the actual issue lies deeper in the incomplete `CASE` expression inside the `charlson_conditions` CTE.
- The critical error is in the `Metastatic tumor` line: `MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code BETWEEN 'C78' AND 'C79') THEN 1 ELSE 0 END) AS metastatic,` — but the code is cut off mid-expression with `THEN 1 ELSE 0 END) AS metastatic,` followed by nothing. Worse, earlier in the CTE, the line ends with `THEN 1 ELSE 0 END) AS metastatic,` but the condition is incomplete and ends with `AND d.icd_code BETWEEN 'C00' AND 'C97') THEN 1 ELSE 0 END) AS cancer,` — and then `MAX(CASE WHEN (;` which is syntactically invalid.
- The `MAX(CASE WHEN (;` line is clearly incomplete and causes the parser to fail. This must be completed or removed.
- Additionally, the `AIDS` condition is missing, and the `Charlson` score calculation is not yet implemented.
- We must complete the `charlson_conditions` CTE with all required conditions, including `metastatic` and `aids`, and then compute the `charlson_score` in a subsequent CTE.
- We also define `CKD` as `N18`, `N19`, or `Z99.2`, and `diabetes` as any `E11`, `E10`, or `E13` code.
- The `icu_status` CTE is correctly refactored to use `LEFT JOIN` to avoid duplication.
- We then join all components: filter patients, admissions with complications, ICU status, LOS, and comorbidities.
- Finally, we stratify by ICU group, LOS group, and Charlson group, and compute mortality (%), median LOS, and CKD/diabetes prevalence.

Key fixes:
1. Complete the `metastatic` and `aids` conditions in `charlson_conditions`.
2. Fix the incomplete `CASE` expression that caused the syntax error.
3. Add `charlson_score` calculation using standard Charlson weights.
4. Define `ckd_flag` and `diabetes_flag` in a separate CTE or within `charlson_conditions`.
5. Ensure all CTEs are properly chained and joined.

sql
WITH patients_filtered AS (
  SELECT p.subject_id, p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 51 AND 61
),

-- Identify admissions with postoperative complications
admissions_complications AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (LOWER(d.long_title) LIKE '%complication%' AND LOWER(d.long_title) LIKE '%postoperative%')
     OR (di.icd_version = 10 AND di.icd_code LIKE 'T81%')
     OR (di.icd_version = 10 AND di.icd_code LIKE 'T82%')
     OR (di.icd_version = 10 AND di.icd_code LIKE 'T85%')
),

-- ICU status per admission: use LEFT JOIN to avoid duplicates
icu_status AS (
  SELECT a.hadm_id,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'non-ICU' END AS icu_group
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON a.hadm_id = i.hadm_id
),

-- Hospital LOS and mortality
los_data AS (
  SELECT hadm_id,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions
),

-- Charlson conditions, CKD, and diabetes flags
charlson_conditions AS (
  SELECT di.hadm_id,
    -- Myocardial infarction
    MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code IN ('I21', 'I22')) THEN 1 ELSE 0 END) AS mi,
    -- Congestive heart failure
    MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code LIKE 'I50%') THEN 1 ELSE 0 END) AS chf,
    -- Peripheral vascular disease
    MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code IN ('I73.9', 'I70.2', 'I70.3')) THEN 1 ELSE 0 END) AS pvd,
    -- Stroke
    MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code IN ('I63', 'I64')) THEN 1 ELSE 0 END) AS stroke,
    -- Dementia
    MAX(CASE WHEN (d.icd_version = 10 AND (d.icd_code LIKE 'F01%' OR d.icd_code LIKE 'F03%')) THEN 1 ELSE 0 END) AS dementia,
    -- COPD
    MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code LIKE 'J44%') THEN 1 ELSE 0 END) AS copd,
    -- Rheumatic disease
    MAX(CASE WHEN (d.icd_version = 10 AND (d.icd_code LIKE 'M05%' OR d.icd_code LIKE 'M06%')) THEN 1 ELSE 0 END) AS rheum,
    -- Peptic ulcer disease
    MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code IN ('K25', 'K26', 'K27', 'K28')) THEN 1 ELSE 0 END) AS pud,
    -- Mild liver disease
    MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code IN ('B18.1', 'B18.2', 'K70.0', 'K70.1', 'K70.2', 'K70.3', 'K71.3', 'K71.4', 'K71.5', 'K71.7', 'K73', 'K74.0', 'K74.1', 'K74.2', 'K74.3', 'K74.4', 'K74.5', 'K74.6')) THEN 1 ELSE 0 END) AS liver_mild,
    -- Moderate/severe liver disease (simplified)
    MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code = 'K74.6') THEN 1 ELSE 0 END) AS liver_severe,
    -- Diabetes without complications
    MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code = 'E11.9') THEN 1 ELSE 0 END) AS diabetes_uncomp,
    -- Diabetes with complications
    MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code IN ('E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8')) THEN 1 ELSE 0 END) AS diabetes_comp,
    -- Hemiplegia
    MAX(CASE WHEN (d.icd_version = 10 AND (d.icd_code LIKE 'G81%' OR d.icd_code LIKE 'G82%')) THEN 1 ELSE 0 END) AS hemiplegia,
    -- Renal disease (CKD)
    MAX(CASE WHEN (d.icd_version = 10 AND (d.icd_code LIKE 'N18%' OR d.icd_code LIKE 'N19%')) THEN 1 ELSE 0 END) AS renal,
    -- Any cancer
    MAX(CASE WHEN (d.icd_version = 10 AND d.icd;