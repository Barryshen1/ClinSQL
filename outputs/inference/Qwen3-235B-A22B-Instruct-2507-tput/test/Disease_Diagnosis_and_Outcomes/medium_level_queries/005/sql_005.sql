with narrative text: `heart failure (HF). Age must be calculated...`, which is not valid SQL and causes the parser to fail immediately.
- The actual SQL code begins later with `WITH first_admissions AS (...)`, but the leading non-SQL text must be removed for the query to be valid.
- Additionally, the `charlson_comorbidities` CTE is cut off mid-`CASE` statement (ends with `MAX(CASE WHEN d.icd_code IN ('I85', 'I98.3') OR d.icd_code LIKE 'K70%' ... THEN 1 ELSE 0 END) AS mod_sev_liver,` and then abruptly ends with `-- Metastatic;`). This incomplete `CASE` logic and missing closing parenthesis/alias will cause a syntax error.
- We must complete the `charlson_comorbidities` CTE by adding the missing comorbidities: Metastatic tumor (6 points), and AIDS (6 points), and ensure all `CASE` expressions are properly closed.
- The `charlson_comorbidities` should aggregate per `subject_id` using `GROUP BY subject_id`.
- After computing the presence of each comorbidity, we calculate the Charlson score by summing the weighted conditions and categorize it into groups (≤3, 4–5, >5). We also compute the comorbidity count as the number of distinct conditions present.
- Finally, we join this back to the `icu_flag` CTE on `subject_id` and group by ICU status, LOS group, and Charlson group to compute in-hospital mortality (%) with 95% CI and mean comorbidity count.

Key fixes:
1. Remove all non-SQL text before `WITH`.
2. Complete the `charlson_comorbidities` CTE with all conditions, including Metastatic tumor and AIDS.
3. Add `GROUP BY subject_id` in `charlson_comorbidities`.
4. Compute Charlson score and comorbidity count in a new CTE.
5. Join comorbidity data to main cohort and compute final statistics.

sql
WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
-- Filter patients aged 38-48 at admission
eligible_patients AS (
  SELECT *
  FROM first_admissions
  WHERE age_at_admit BETWEEN 38 AND 48
),
-- Get first admission per patient
first_adm_per_patient AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM eligible_patients
),
cohort AS (
  SELECT *
  FROM first_adm_per_patient
  WHERE rn = 1
),
-- Heart failure diagnosis: ICD-10 I50.*
hf_patients AS (
  SELECT DISTINCT c.*
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON c.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code LIKE 'I50%' AND d.icd_version = 10
),
-- Compute LOS in days
los_strat AS (
  SELECT *,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) >= 8 THEN '>=8'
      ELSE NULL
    END AS los_group
  FROM hf_patients
),
-- ICU flag: if patient had any ICU stay
icu_flag AS (
  SELECT
    l.*,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS had_icu
  FROM los_strat l
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON l.hadm_id = i.hadm_id
),
-- Map all diagnoses to Charlson comorbidities (using ICD-10 codes)
charlson_comorbidities AS (
  SELECT
    di.subject_id,
    -- Myocardial infarction (1 point)
    MAX(CASE WHEN d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' THEN 1 ELSE 0 END) AS mi,
    -- Congestive heart failure (1 point) - already in cohort
    MAX(CASE WHEN d.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS chf,
    -- Peripheral vascular disease (1 point)
    MAX(CASE WHEN d.icd_code BETWEEN 'I70' AND 'I79' THEN 1 ELSE 0 END) AS pvd,
    -- Cerebrovascular disease (1 point)
    MAX(CASE WHEN d.icd_code BETWEEN 'I60' AND 'I69' THEN 1 ELSE 0 END) AS cvd,
    -- Dementia (1 point)
    MAX(CASE WHEN d.icd_code BETWEEN 'F01' AND 'F03' THEN 1 ELSE 0 END) AS dementia,
    -- Chronic pulmonary disease (1 point)
    MAX(CASE WHEN d.icd_code BETWEEN 'J40' AND 'J47' THEN 1 ELSE 0 END) AS copd,
    -- Rheumatic disease (1 point)
    MAX(CASE WHEN d.icd_code BETWEEN 'M05' AND 'M06' THEN 1 ELSE 0 END) AS rheum,
    -- Peptic ulcer disease (1 point)
    MAX(CASE WHEN d.icd_code BETWEEN 'K25' AND 'K26' THEN 1 ELSE 0 END) AS pud,
    -- Mild liver disease (1 point)
    MAX(CASE WHEN d.icd_code IN ('B18') OR d.icd_code BETWEEN 'K73' AND 'K74' THEN 1 ELSE 0 END) AS mild_liver,
    -- Diabetes without complications (1 point)
    MAX(CASE WHEN d.icd_code LIKE 'E11%' AND d.icd_code NOT LIKE 'E11.2%' AND d.icd_code NOT LIKE 'E11.3%' 
             AND d.icd_code NOT LIKE 'E11.4%' AND d.icd_code NOT LIKE 'E11.5%' AND d.icd_code NOT LIKE 'E11.6%'
             AND d.icd_code NOT LIKE 'E11.7%' AND d.icd_code NOT LIKE 'E11.8%' AND d.icd_code NOT LIKE 'E11.9%' THEN 1 ELSE 0 END) AS dm_no_comp,
    -- Diabetes with complications (2 points)
    MAX(CASE WHEN d.icd_code LIKE 'E11.2%' OR d.icd_code LIKE 'E11.3%' OR d.icd_code LIKE 'E11.4%'
              OR d.icd_code LIKE 'E11.5%' OR d.icd_code LIKE 'E11.6%' OR d.icd_code LIKE 'E11.7%'
              OR d.icd_code LIKE 'E11.8%' OR d.icd_code LIKE 'E11.9%' THEN 1 ELSE 0 END) AS dm_w_comp,
    -- Hemiplegia (2 points)
    MAX(CASE WHEN d.icd_code LIKE 'G81%' THEN 1 ELSE 0 END) AS hemo,
    -- Moderate/severe renal disease (2 points)
    MAX(CASE WHEN d.icd_code BETWEEN 'N18.2' AND 'N18.6' THEN 1 ELSE 0 END) AS mslrd,
    -- Any malignancy (2 points)
    MAX(CASE WHEN d.icd_code BETWEEN 'C00' AND 'C97' THEN 1 ELSE 0 END) AS cancer,
    -- Moderate/severe liver disease (3 points)
    MAX(CASE WHEN d.icd_code IN ('I85', 'I98.3') OR d.icd_code LIKE 'K70%' 
              OR d.icd_code BETWEEN 'K71.3' AND 'K71.5' OR d.icd_code BETWEEN 'K72' AND 'K74' THEN;