with `WITH `icd_version = 2`` — this is invalid SQL syntax. The `WITH` clause must define Common Table Expressions (CTEs) using `AS (...)`, not assign scalar values or conditions.
- The `charlson_weights` CTE is cut off mid-statement, specifically within a `SUBSTR(icd_code, 1, 3) = 'C91' AND LENGTH(icd_code) = 3 THEN 2 -- Leukemia` line, which breaks the entire query.
- The incomplete `CASE` statement and missing `END` cause parsing failure.
- Additionally, the ICD-10 cancer code handling (`WHEN SUBSTR(icd_code, 1, 1) = 'C' THEN 2`) is correct in principle but should be placed logically and completed before the cutoff.
- We must complete the `CASE` expression in `charlson_weights`, ensure all `WHEN` branches are properly closed with `END`, and remove any invalid syntax before `WITH`.
- The rest of the logic (age filtering, ICU flag, LOS calculation) is sound and can be preserved with minor fixes.

Key fixes:
1. Remove the invalid `WITH `icd_version = 2`` line — it's not valid BigQuery SQL.
2. Complete the `charlson_weights` CTE by finishing the `CASE` expression, including the leukemia and lymphoma conditions, and properly closing the `CASE`.
3. Ensure all parentheses and `END` keywords are present.
4. Join `diagnoses_icd` with `charlson_weights` to compute per-admission Charlson score.
5. Aggregate results by ICU status, LOS group, and Charlson group to compute mortality %, count (N), and median time-to-death.

Final query includes:
- Proper CTE structure.
- Complete Charlson mapping for ICD-10 and ICD-9.
- Computation of Charlson score per `hadm_id`.
- Grouping by ICU status, LOS strata (1–3, 4–7, ≥8), and Charlson strata (≤3, 4–5, >5).
- In-hospital mortality rate and median time-to-death (only for deceased patients).

sql
WITH age_calc AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    (DATETIME_DIFF(a.admittime, MAKE_DATETIME(p.anchor_year, 1, 1, 0, 0, 0), DAY) / 365.25 + p.anchor_age) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
),
cohort AS (
  SELECT *
  FROM age_calc
  WHERE gender = 'M'
    AND age_at_admit >= 60 AND age_at_admit <= 70
),
icu_flag AS (
  SELECT
    subject_id,
    hadm_id,
    TRUE AS in_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY subject_id, hadm_id
),
cohort_with_icu AS (
  SELECT
    c.*,
    COALESCE(i.in_icu, FALSE) AS icu_status
  FROM cohort c
  LEFT JOIN icu_flag i ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
),
los_calc AS (
  SELECT
    *,
    DATETIME_DIFF(dischtime, admittime, DAY) AS hosp_los_days
  FROM cohort_with_icu
),
-- Charlson Comorbidity Index mapping (Quan adaptation for ICD-9-CM and ICD-10-CM)
charlson_weights AS (
  SELECT
    icd_code,
    icd_version,
    CASE
      WHEN icd_version = 9 THEN
        CASE
          WHEN icd_code IN ('491', '492', '496') THEN 1 -- COPD
          WHEN icd_code IN ('25000', '25001', '25003') THEN 1 -- Diabetes w/o complications
          WHEN icd_code IN ('25040', '25041', '25043') THEN 2 -- Diabetes with complications
          WHEN icd_code BETWEEN '41510' AND '41519' THEN 1 -- Pulmonary embolism
          WHEN icd_code IN ('585', '586', 'V56') THEN 2 -- Renal disease
          WHEN icd_code BETWEEN '5990' AND '5999' THEN 2 -- Urinary tract infection (as proxy for renal)
          WHEN SUBSTR(icd_code, 1, 3) IN ('140','141','142','143','144','145','146','147','148','149',
                                         '150','151','152','153','154','155','156','157','158','159',
                                         '160','161','162','163','200','201','202','203','204','205',
                                         '206','207','208') THEN 2 -- Solid tumor, leukemia, lymphoma
          WHEN icd_code IN ('40301','40311','40391','40402','40403','40412','40413','40492','40493') THEN 2 -- Hypertensive renal disease
          WHEN icd_code IN ('4280','4281','42821','42822','42823','42831','42832','42833','42841','42842','42843','4289') THEN 1 -- CHF
          WHEN icd_code BETWEEN '410' AND '414' THEN 1 -- Myocardial infarction
          WHEN icd_code BETWEEN '430' AND '438' THEN 1 -- Cerebrovascular disease
          WHEN icd_code IN ('5712','5714','5715','5716') THEN 1 -- Mild liver disease
          WHEN icd_code IN ('5717','4560','4561','4562','5722','5723','5724','5728') THEN 3 -- Moderate/severe liver
          WHEN icd_code IN ('042','043','044') THEN 6 -- AIDS
          WHEN icd_code BETWEEN '20500' AND '20503' THEN 2 -- Leukemia
          WHEN icd_code BETWEEN '20510' AND '20513' THEN 2 -- Lymphoma
          ELSE 0
        END
      WHEN icd_version = 10 THEN
        CASE
          WHEN SUBSTR(icd_code, 1, 3) IN ('J44', 'J43', 'J45', 'J46') THEN 1 -- COPD
          WHEN SUBSTR(icd_code, 1, 3) = 'E11' AND LENGTH(icd_code) = 3 THEN 1 -- Diabetes w/o complications
          WHEN SUBSTR(icd_code, 1, 4) IN ('E114', 'E115', 'E116', 'E117', 'E118') THEN 2 -- Diabetes with complications
          WHEN SUBSTR(icd_code, 1, 3) = 'I26' THEN 1 -- Pulmonary embolism
          WHEN SUBSTR(icd_code, 1, 3) IN ('N18', 'N19') THEN 2 -- Chronic kidney disease
          WHEN SUBSTR(icd_code, 1, 1) = 'C' THEN 2 -- All malignant neoplasms (C00-C97)
          WHEN SUBSTR(icd_code, 1, 3) IN ('I12', 'I13', 'I15') THEN 2 -- Hypertensive renal disease
          WHEN SUBSTR(icd_code, 1, 3) IN ('I50') THEN 1 -- Congestive heart failure
          WHEN SUBSTR(icd_code, 1, 3) BETWEEN 'I21' AND 'I25' THEN 1 -- MI
          WHEN SUBSTR(icd_code, 1, 3) BETWEEN 'I60' AND 'I69' THEN 1 -- Cerebrovascular disease
          WHEN SUBSTR;