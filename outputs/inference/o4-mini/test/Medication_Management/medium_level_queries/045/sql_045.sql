WITH cohort AS (
  -- 1. Identify female inpatients age 54-64 with both diabetes and heart failure
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 54 AND 64
    -- inpatient stays (discharge_location not null)
    AND a.discharge_location IS NOT NULL
    -- must have diabetes
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND dd.icd_code LIKE 'E1%'  -- diabetes (ICD-10 E10–E14)
    )
    -- must have heart failure
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND dd.icd_code LIKE 'I50%'  -- heart failure (ICD-10 I50)
    )
),
meds AS (
  -- 2. Extract prescriptions in the relevant time windows and classify
  SELECT
    c.hadm_id,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN p.route = 'ORAL' THEN 'oral'
      ELSE NULL
    END AS drug_class,
    p.starttime,
    p.stoptime,
    c.admittime,
    c.dischtime
  FROM
    cohort AS c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
      ON p.hadm_id = c.hadm_id
  WHERE
    LOWER(p.drug) LIKE '%insulin%'
    OR p.route = 'ORAL'
),
flagged AS (
  -- 3. For each admission, flag whether each drug class occurred in each period
  SELECT
    hadm_id,
    MAX(CASE
          WHEN drug_class = 'insulin'
           AND starttime BETWEEN admittime AND admittime + INTERVAL 12 HOUR
          THEN 1 ELSE 0 END) AS insulin_first12,
    MAX(CASE
          WHEN drug_class = 'oral'
           AND starttime BETWEEN admittime AND admittime + INTERVAL 12 HOUR
          THEN 1 ELSE 0 END) AS oral_first12,
    MAX(CASE
          WHEN drug_class = 'insulin'
           AND stoptime BETWEEN dischtime - INTERVAL 48 HOUR AND dischtime
          THEN 1 ELSE 0 END) AS insulin_last48,
    MAX(CASE
          WHEN drug_class = 'oral'
           AND stoptime BETWEEN dischtime - INTERVAL 48 HOUR AND dischtime
          THEN 1 ELSE 0 END) AS oral_last48
  FROM
    meds
  GROUP BY
    hadm_id
),
totals AS (
  -- 4. Compute denominator
  SELECT
    COUNT(DISTINCT hadm_id) AS total_admissions
  FROM
    cohort
)
-- 5. Final aggregation: prevalence and net change
SELECT
  ROUND(100.0 * SUM(insulin_first12)   / ANY_VALUE(t.total_admissions), 1) AS insulin_pct_first12,
  ROUND(100.0 * SUM(oral_first12)      / ANY_VALUE(t.total_admissions), 1) AS oral_pct_first12,
  ROUND(100.0 * SUM(insulin_last48)    / ANY_VALUE(t.total_admissions), 1) AS insulin_pct_last48,
  ROUND(100.0 * SUM(oral_last48)       / ANY_VALUE(t.total_admissions), 1) AS oral_pct_last48,
  ROUND(
    100.0 * SUM(insulin_last48) / ANY_VALUE(t.total_admissions)
    - 100.0 * SUM(insulin_first12) / ANY_VALUE(t.total_admissions)
  , 1) AS net_change_pp_insulin,
  ROUND(
    100.0 * SUM(oral_last48) / ANY_VALUE(t.total_admissions)
    - 100.0 * SUM(oral_first12) / ANY_VALUE(t.total_admissions)
  , 1) AS net_change_pp_oral
FROM
  flagged f
  CROSS JOIN totals t;