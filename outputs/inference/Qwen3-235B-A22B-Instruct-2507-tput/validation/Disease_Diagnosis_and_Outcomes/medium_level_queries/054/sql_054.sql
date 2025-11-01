with proper ICD-10 code mappings and closed with `END` before the alias `AS charlson_weight`.
- Additionally, the entire `charlson_map` CTE is missing the `AS charlson_weight` alias assignment and proper `END` for the outer `CASE`, which is required in BigQuery.
- We must ensure that both ICD-9 and ICD-10 codes are handled correctly using `SUBSTR(icd_code, 1, 3)` for three-digit code matching.
- The query also needs to:
  - Aggregate the Charlson score per `hadm_id` from `diagnoses_icd`.
  - Join with admissions to get ICU flag, LOS, and mortality.
  - Define LOS groups (≤3, 4–6, 7–10, >10) and Charlson groups (≤3, 4–5, >5).
  - Compute in-hospital mortality %, mechanical ventilation %, vasopressors %, RRT %.
  - Compute absolute and relative difference in mortality vs the ≤3-day LOS group within each ICU/non-ICU stratum.

We reconstruct the `charlson_map` with complete logic for both ICD versions and ensure all `CASE` statements are properly closed.

Key fixes:
1. Complete the truncated ICD-10 `CASE` logic.
2. Add missing `END` keywords and proper aliasing.
3. Aggregate Charlson score per admission.
4. Define LOS and Charlson groups.
5. Compute required metrics with window functions for baseline comparison.

sql
WITH patients_44m AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'M' AND anchor_age = 44
),

admissions_with_los AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_44m p ON a.subject_id = p.subject_id
),

icu_flag AS (
  SELECT
    hadm_id,
    1 AS icu_stay
  FROM `physionet-data.mimiciv_3_1_icu`.icustays
  GROUP BY hadm_id
),

admissions_icu AS (
  SELECT
    a.*,
    COALESCE(i.icu_stay, 0) AS icu_flag
  FROM admissions_with_los a
  LEFT JOIN icu_flag i ON a.hadm_id = i.hadm_id
),

-- Charlson Comorbidity Index mapping for ICD-9 and ICD-10
charlson_map AS (
  SELECT
    icd_code,
    icd_version,
    CASE
      WHEN icd_version = 9 THEN
        CASE
          WHEN SUBSTR(icd_code, 1, 3) IN ('410','412') THEN 1  -- Myocardial infarction
          WHEN SUBSTR(icd_code, 1, 3) IN ('428') THEN 1        -- Congestive heart failure
          WHEN SUBSTR(icd_code, 1, 3) IN ('440','441') THEN 1   -- Peripheral vascular disease
          WHEN SUBSTR(icd_code, 1, 3) IN ('430','431','432','433','434','435','436','437','438') THEN 1  -- Cerebrovascular disease
          WHEN SUBSTR(icd_code, 1, 3) IN ('290','294','331') THEN 1  -- Dementia
          WHEN SUBSTR(icd_code, 1, 3) IN ('490','491','492','493','494','495','496','500','501','502','503','504','505') THEN 1  -- COPD
          WHEN SUBSTR(icd_code, 1, 3) IN ('093','094','710','714') THEN 1  -- Connective tissue disease
          WHEN SUBSTR(icd_code, 1, 3) IN ('531','532','533','534') THEN 1  -- Peptic ulcer
          WHEN SUBSTR(icd_code, 1, 3) IN ('571') AND SUBSTR(icd_code, 4, 1) NOT IN ('5','6') THEN 1  -- Mild liver disease
          WHEN SUBSTR(icd_code, 1, 3) IN ('571','456','572') AND (SUBSTR(icd_code, 4, 1) IN ('5','6') OR icd_code IN ('572.2','572.3','572.4','572.8')) THEN 3  -- Moderate/severe liver
          WHEN SUBSTR(icd_code, 1, 3) IN ('250') AND SUBSTR(icd_code, 4, 1) NOT IN ('0') THEN 1  -- Diabetes without complications
          WHEN SUBSTR(icd_code, 1, 3) IN ('250') AND SUBSTR(icd_code, 4, 1) IN ('1','2','3') THEN 2  -- Diabetes with complications
          WHEN SUBSTR(icd_code, 1, 3) IN ('342','343') THEN 2  -- Hemiplegia
          WHEN SUBSTR(icd_code, 1, 3) IN ('582','585','586','V56') OR (SUBSTR(icd_code, 1, 3) = '403' AND SUBSTR(icd_code, 4, 1) = '1') THEN 2  -- Renal disease
          WHEN SUBSTR(icd_code, 1, 3) IN ('140','141','142','143','144','145','146','147','148','149','150','151','152','153','154','155','156','157','158','159','160','161','162','163','170','171','172','174','175','176','177','178','179','180','181','182','183','184','185','186','187','188','189','190','191','192','193','194','195') THEN 6  -- Tumor
          WHEN SUBSTR(icd_code, 1, 3) IN ('196','197','198','199') THEN 6  -- Metastatic solid tumor
          WHEN SUBSTR(icd_code, 1, 3) IN ('200','201','202') THEN 6  -- Leukemia
          WHEN SUBSTR(icd_code, 1, 3) IN ('203') AND SUBSTR(icd_code, 4, 1) NOT IN ('2','3') THEN 6
          WHEN SUBSTR(icd_code, 1, 3) IN ('204','205','206','207') AND SUBSTR(icd_code, 4, 1) NOT IN ('2','3') THEN 6
          WHEN SUBSTR(icd_code, 1, 3) IN ('042','043','044') THEN 6  -- AIDS
        ELSE 0
        END
      WHEN icd_version = 10 THEN
        CASE
          WHEN SUBSTR(icd_code, 1, 3) IN ('I21','I22') THEN 1  -- Myocardial infarction
          WHEN SUBSTR(icd_code, 1, 3) IN ('I50') THEN 1        -- Congestive heart failure
          WHEN SUBSTR(icd_code, 1, 3) IN ('I70','I71') THEN 1   -- Peripheral vascular disease
          WHEN SUBSTR(icd_code, 1,;