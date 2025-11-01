with `with pulmonary embolism (PE) using ICD diagnoses...`) that is not properly formatted for SQL.
- In BigQuery, comments must be prefixed with `--` for single-line or enclosed in `/* ... */` for multi-line. The initial text is plain English and not commented out, so BigQuery tries to parse it as SQL, failing when it encounters the word "embolism".
- The fix is to either remove this explanatory text or wrap it in proper SQL comment syntax. Since this is a code submission, we should remove the unstructured commentary and begin directly with the SQL.
- Additionally, the `comorbidities` CTE is incomplete (cut off mid-statement), so we must complete the Elixhauser comorbidity list with representative conditions, ensuring valid syntax and closing parentheses.
- We will define AKI and ARDS using ICD codes (e.g., AKI: ICD-10 'N17%', ICD-9 '584'; ARDS: ICD-10 'J80', ICD-9 '51882').
- We compute comorbidity count as a sum of binary flags, then assign quintiles using `NTILE(5) OVER (ORDER BY comorbidity_count)`.
- We calculate outcomes: 90-day mortality, AKI, ARDS, and median LOS for survivors (patients who did not die in hospital).
- Separately, we compute the 90-day mortality rate for all females aged 70–80 without PE for comparison.

Key changes:
- Remove non-SQL commentary at the top.
- Fix incomplete `comorbidities` CTE with proper syntax and additional conditions.
- Join diagnoses to compute comorbidities for all patients in `patient_admissions`, not just PE cohort, to allow comparison.
- Stratify PE cohort by comorbidity count quintiles.
- Add logic for AKI and ARDS via ICD codes.
- Compute comparison group: 90-day mortality in non-PE females 70–80.

sql
WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit,
    -- 90-day mortality: died within 90 days of admission
    CASE WHEN p.dod IS NOT NULL AND p.dod <= DATETIME_ADD(a.admittime, INTERVAL 90 DAY) THEN 1 ELSE 0 END AS died_within_90d,
    -- Hospital LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 70 AND 80
),
-- Get ICD codes for each admission
diagnoses AS (
  SELECT 
    di.hadm_id,
    di.icd_code,
    di.icd_version,
    d_icd.long_title
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_icd
    ON di.icd_code = d_icd.icd_code AND di.icd_version = d_icd.icd_version
),
-- Identify patients with Pulmonary Embolism (PE)
pe_cohort AS (
  SELECT DISTINCT pa.*
  FROM patient_admissions pa
  INNER JOIN diagnoses d ON pa.hadm_id = d.hadm_id
  WHERE (d.icd_version = 9 AND d.icd_code = '4151')   -- ICD-9: 415.1
     OR (d.icd_version = 10 AND d.icd_code = 'I269')  -- ICD-10: I26.9
),
-- All diagnoses for comorbidity and outcome extraction
all_diagnoses AS (
  SELECT
    hadm_id,
    icd_code,
    icd_version
  FROM diagnoses
),
-- Elixhauser comorbidities (simplified list; representative conditions)
comorbidity_scores AS (
  SELECT
    pa.hadm_id,
    SUM(
      CASE 
        -- Congestive heart failure
        WHEN (ad.icd_version = 9 AND ad.icd_code IN ('39891', '40201', '40211', '40291', '40401', '40403', '40411', '40413', '40491', '40493', '4280', '4281', '42820', '42821', '42822', '42823', '42830', '42831', '42832', '42833', '42840', '42841', '42842', '42843', '4289')) 
             OR (ad.icd_version = 10 AND ad.icd_code LIKE 'I110' OR ad.icd_code LIKE 'I130' OR ad.icd_code LIKE 'I132' OR ad.icd_code LIKE 'I255' OR ad.icd_code LIKE 'I420' OR ad.icd_code LIKE 'I425' OR ad.icd_code LIKE 'I426' OR ad.icd_code LIKE 'I427' OR ad.icd_code LIKE 'I428' OR ad.icd_code LIKE 'I429' OR ad.icd_code LIKE 'I43' OR ad.icd_code LIKE 'I50%')
          THEN 1 ELSE 0 END
    ) AS congestive_heart_failure,
    SUM(
      CASE 
        -- Cardiac arrhythmias
        WHEN (ad.icd_version = 9 AND ad.icd_code IN ('4260', '42613', '4267', '4269', '4270', '4271', '4272', '42731', '4276', '42781', '4279')) 
             OR (ad.icd_version = 10 AND (ad.icd_code LIKE 'I44%' OR ad.icd_code LIKE 'I45%' OR ad.icd_code LIKE 'I46%' OR ad.icd_code LIKE 'I47%' OR ad.icd_code LIKE 'I48%' OR ad.icd_code LIKE 'I49%'))
          THEN 1 ELSE 0 END
    ) AS cardiac_arrhythmias,
    SUM(
      CASE 
        -- Valvular disease
        WHEN (ad.icd_version = 9 AND ad.icd_code IN ('09320', '09324', '3940', '3941', '3942', '3943', '3949', '3950', '3951', '3952', '3953', '3954', '3959', '3960', '3961', '3962', '3963', '3968', '3969', '3970', '3971', '3979', '7463', '7464', '7465', '7466'))
             OR (ad.icd_version = 10 AND (ad.icd_code LIKE 'A09%' OR ad.icd_code LIKE 'I05%' OR ad.icd_code LIKE 'I06%' OR ad.icd_code LIKE 'I07%' OR ad.icd_code LIKE 'I08%' OR ad.icd_code LIKE 'I091' OR ad.icd_code LIKE 'I34%' OR ad.icd_code LIKE 'I35%' OR ad.icd_code LIKE 'I36%' OR ad.icd_code LIKE 'I37%' OR ad.icd_code LIKE 'I38%' OR ad.icd_code LIKE 'I39%' OR ad.icd_code LIKE 'Q23%'))
          THEN 1 ELSE 0 END
    ) AS valvular_disease,
    SUM(
      CASE 
        -- Peripheral vascular disease
        WHEN (ad.icd_version = 9 AND ad.icd_code IN ('0930', '4400', '4401', '440;