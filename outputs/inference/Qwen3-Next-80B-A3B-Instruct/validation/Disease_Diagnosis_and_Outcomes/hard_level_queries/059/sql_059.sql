with DKA** (Diabetic Ketoacidosis).` were likely copied from a source with smart quotes or Unicode formatting (e.g., Word or Markdown), which BigQuery cannot parse. BigQuery SQL requires pure ASCII characters for identifiers and syntax.

Additionally, the SQL query is incomplete — the final CTE `general_hospital_score` is cut off and lacks the final SELECT that would compute the required metrics (30-day mortality, AKI/ARDS rates, LOS comparison, and percentile). We must complete the logic as intended.

Key fixes needed:

1. Remove the malformed comment `with DKA** (Diabetic Ketoacidosis).` — it’s not valid SQL and causes the Unicode error.
2. Fix all dataset references: use backticks around dataset names containing hyphens: `physionet-data.mimiciv_3_1_hosp` → `'physionet-data.mimiciv_3_1_hosp'` (BigQuery requires backticks for identifiers with hyphens).
3. Complete the `general_hospital_score` CTE and add missing CTEs for:
   - AKI diagnosis (ICD codes: 250.1x, E10.1x, E11.1x, E13.1x — already used for DKA, but AKI is separate: ICD-9 584.x, ICD-10 N17.x)
   - ARDS diagnosis (ICD-9 518.5, ICD-10 J80)
   - 30-day mortality: check if `dod` is within 30 days of `admittime`
   - LOS (length of stay) for survivors in DKA vs general cohort
   - Percentile of DKA mean score within general cohort distribution
4. Use `DATE_ADD(admittime, INTERVAL 30 DAY)` for 30-day mortality window.
5. Use `PERCENTILE_CONT` on the general cohort’s individual HOSPITAL scores to get the percentile rank of the DKA mean.
6. Ensure all `JOIN`s use correct dataset prefixes with backticks.
7. Fix the `UNION ALL` subquery in `hospital_score_components` — it references CTEs `dka_cohort` and `general_cohort` which are defined later. In BigQuery, CTEs must be referenced only after they are defined, so we must restructure to avoid forward references.

We’ll restructure the query to define CTEs in dependency order and complete all required outputs.

Final output will include:
- Mean HOSPITAL score for DKA cohort
- 30-day mortality rate for DKA cohort
- AKI rate (ICD-9: 584.x, ICD-10: N17.x) in DKA vs general
- ARDS rate (ICD-9: 518.5, ICD-10: J80) in DKA vs general
- Median LOS for survivors in DKA vs general
- Percentile of DKA’s mean HOSPITAL score within the general cohort’s distribution

sql
WITH dka_cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.dod, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp`.`patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp`.`admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.`diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.`d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.anchor_age BETWEEN 59 AND 69
    AND p.gender = 'M'
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '250.1%')
      OR (d.icd_version = 10 AND d.icd_code IN ('E10.10', 'E10.11', 'E11.10', 'E11.11', 'E13.10', 'E13.11'))
    )
),

general_cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.dod, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp`.`patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp`.`admissions` a ON p.subject_id = a.subject_id
  WHERE p.anchor_age BETWEEN 59 AND 69
    AND p.gender = 'M'
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.`diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp`.`d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE a.hadm_id = d.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250.1%')
          OR (d.icd_version = 10 AND d.icd_code IN ('E10.10', 'E10.11', 'E11.10', 'E11.11', 'E13.10', 'E13.11'))
        )
    )
),

hospital_score_components AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN le.itemid = 50813 AND le.valuenum < 13 THEN 1 ELSE 0 END) AS hemoglobin_low,  -- male
    MAX(CASE WHEN le.itemid = 50983 AND (le.valuenum < 135 OR le.valuenum > 145) THEN 1 ELSE 0 END) AS sodium_abnormal,
    MAX(CASE WHEN ce.itemid = 51 AND ce.valuenum < 100 THEN 1 ELSE 0 END) AS systolic_bp_low,
    MAX(CASE WHEN le.itemid = 51265 AND le.valuenum < 150000 THEN 1 ELSE 0 END) AS platelets_low,
    MAX(CASE WHEN a.admission_type != 'elective' THEN 1 ELSE 0 END) AS inpatient_admission,
    MAX(CASE WHEN ce.itemid = 223762 AND (ce.valuenum > 38.5 OR ce.valuenum < 36) THEN 1 ELSE 0 END) AS temperature_abnormal,
    MAX(CASE WHEN le.itemid = 50862 AND le.valuenum < 3.5 THEN 1 ELSE 0 END) AS albumin_low
  FROM (
    SELECT subject_id, hadm_id, admittime FROM dka_cohort
    UNION ALL
    SELECT subject_id, hadm_id, admittime FROM general_cohort
  ) c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.`labevents` le
    ON c.subject_id = le.subject_id
    AND le.charttime BETWEEN c.admittime AND DATE_ADD(c.admittime, INTERVAL 24 HOUR)
    AND le.itemid IN (50813, 50983, 51265, 50862)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.`chartevents` ce
    ON c.subject_id = ce.subject_id
    AND ce.charttime BETWEEN c.admittime AND DATE_ADD(c.admittime, INTERVAL 24 HOUR)
    AND ce.itemid IN (51, 223762)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.`admissions` a ON c.hadm_id = a.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.admittime, a.admission_type
),

hospital_score AS (
  SELECT
    subject_id,
    hadm_id,
    (hemoglobin_low + sodium_abnormal + systolic_bp_low + platelets_low + inpatient_admission + temperature_abnormal + albumin_low) AS hospital_score
  FROM hospital_score_components
  WHERE hemoglobin_low IS NOT NULL
    AND sodium_abnormal IS NOT NULL
    AND systolic_bp_low IS NOT NULL
    AND platelets_low IS NOT NULL
    AND inpatient_admission IS NOT NULL
    AND temperature_abnormal IS NOT NULL
    AND albumin_low IS NOT NULL
),

dka_hospital_score AS (
  SELECT AVG(hs.hospital_score) AS mean_hospital_score;