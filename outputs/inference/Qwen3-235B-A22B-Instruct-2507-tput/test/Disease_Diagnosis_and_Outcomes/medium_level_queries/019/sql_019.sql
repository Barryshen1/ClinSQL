with a malformed CTE: `WITH `WITH heart failure (HF). Age is derived...``. This is due to a natural language comment being incorrectly included inside the SQL code before the actual `WITH` clause. BigQuery interprets the text after `WITH` as a CTE name, but it encounters a comma instead of the expected `AS`, leading to a syntax error.
- The fix is to remove all non-SQL commentary before the `WITH` keyword and ensure the SQL begins cleanly with a valid CTE definition.
- Additionally, the `charlson_conditions` CTE was cut off mid-statement (ending with `MAX(CASE WHEN LOWER(d.long;`), which is incomplete and syntactically invalid. This must be completed with proper logic for all Charlson conditions, including correct parentheses and string literals.
- We complete the Charlson conditions using standard ICD-based mappings and assign appropriate weights (e.g., MI=1, CHF=1, DM with complications=2, etc.), then sum the weighted score per patient admission.
- We ensure all string comparisons use `LOWER()` for case insensitivity and that each condition uses proper `LIKE` or equality checks with correct ICD code patterns and versions.
- After computing the Charlson score, we categorize it into groups (≤3, 4–5, >5) and LOS into (1–3, 4–7, ≥8) days.
- Finally, we compute in-hospital mortality %, mean LOS, and discharge destination distribution by these groups.

Key changes:
1. Removed all prose before `WITH`.
2. Completed the `charlson_conditions` CTE with all required conditions and proper syntax.
3. Added `charlson_score` calculation using standard weights.
4. Added categorization for LOS and Charlson.
5. Final aggregation computes mortality %, average LOS, and discharge location % by group.

sql
WITH patients_age AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'M'
),
admissions_age AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.discharge_location,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN patients_age p ON a.subject_id = p.subject_id
),
-- Filter cohort: age 53-63
cohort AS (
  SELECT *
  FROM admissions_age
  WHERE age_at_admission BETWEEN 53 AND 63
),
-- Heart failure diagnosis: use ICD codes
hf_codes AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%heart failure%'
     OR LOWER(d.long_title) LIKE '%cardiomyopathy%'
     OR LOWER(d.long_title) LIKE '%congestive heart failure%'
     OR (di.icd_code LIKE 'I50%' AND di.icd_version = 10)
     OR (di.icd_code LIKE '428%' AND di.icd_version = 9)
),
cohort_hf AS (
  SELECT c.*
  FROM cohort c
  INNER JOIN hf_codes h ON c.subject_id = h.subject_id AND c.hadm_id = h.hadm_id
),
-- Charlson Comorbidity Index calculation
charlson_conditions AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%myocardial infarction%'
              OR (di.icd_code IN ('I21','I22') AND di.icd_version = 10)
              OR (di.icd_code LIKE '410%' AND di.icd_version = 9) THEN 1 ELSE 0 END) AS mi,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%congestive heart failure%'
              OR LOWER(d.long_title) LIKE '%heart failure%'
              OR (di.icd_code LIKE 'I50%' AND di.icd_version = 10)
              OR (di.icd_code LIKE '428%' AND di.icd_version = 9) THEN 1 ELSE 0 END) AS chf,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%peripheral vascular disease%'
              OR (di.icd_code IN ('I70','I71','I73','440','441','443') AND di.icd_version = 10)
              OR (di.icd_code LIKE '44%' AND di.icd_version = 9) THEN 1 ELSE 0 END) AS pvd,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%cerebrovascular disease%'
              OR LOWER(d.long_title) LIKE '%stroke%'
              OR (di.icd_code LIKE 'I6%' AND di.icd_version = 10)
              OR (di.icd_code LIKE '43%' AND di.icd_version = 9) THEN 1 ELSE 0 END) AS stroke,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%dementia%'
              OR (di.icd_code LIKE 'F0%' AND di.icd_version = 10)
              OR (di.icd_code LIKE '29%' AND di.icd_version = 9) THEN 1 ELSE 0 END) AS dementia,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%chronic pulmonary disease%'
              OR LOWER(d.long_title) LIKE '%copd%'
              OR (di.icd_code LIKE 'J44%' AND di.icd_version = 10)
              OR (di.icd_code LIKE '49%' AND di.icd_version = 9) THEN 1 ELSE 0 END) AS copd,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%rheumatic%'
              OR (di.icd_code IN ('M05','M06') AND di.icd_version = 10)
              OR (di.icd_code LIKE '714%' AND di.icd_version = 9) THEN 1 ELSE 0 END) AS rheumatic,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%peptic ulcer%'
              OR (di.icd_code LIKE 'K25%' AND di.icd_version = 10)
              OR (di.icd_code LIKE '531%' AND di.icd_version = 9) THEN 1 ELSE 0 END) AS pud,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%mild liver disease%'
              OR (di.icd_code IN ('K70.3','E86') AND di.icd_version = 10)
              OR (di.icd_code LIKE '571.2%' AND di.icd_version = 9) THEN 1 ELSE 0 END) AS mild_liver,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%moderate or severe liver disease%'
              OR (di.icd_code IN ('I85','K72') AND di.icd_version = 10)
              OR (di.icd_code LIKE '571.5%' AND di.icd_version = 9) THEN 1 ELSE 0 END) AS severe_liver,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%diabetes without complications%'
              OR (di.icd_code LIKE 'E11%' AND di.icd_version = 10 AND di.icd_code NOT LIKE 'E11.2%')
              OR (di.icd_code LIKE '250%' AND di.icd_version = 9 AND di.icd_code NOT LIKE '250.2%') THEN 1 ELSE 0 END) AS dm_no_comp,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%diabetes with complications%'
              OR (di.icd_code LIKE 'E11.2%' AND di.icd_version = 10)
              OR (di.icd_code LIKE '250.2%' AND di.icd_version = 9) THEN 1 ELSE 0 END) AS dm_comp,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%hemiplegia%'
              OR (di.icd_code LIKE 'G81%' AND di.icd_version = 10)
              OR (di.icd_code LIKE '342%' AND di.icd_version = 9) THEN 1 ELSE 0 END) AS hemiplegia,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%renal disease%'
              OR (di.icd_code LIKE 'N18%' AND di.icd_version = 10)
              OR (di.icd_code LIKE '585%' AND di.icd_version = 9) THEN 1 ELSE 0 END) AS renal,
    MAX(CASE WHEN LOWER(d;