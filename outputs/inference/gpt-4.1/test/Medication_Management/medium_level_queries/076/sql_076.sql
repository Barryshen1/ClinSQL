WITH
-- Step 1: Get qualifying admissions (women 75–85, admitted ≥36h, diabetes + acute HF)
base_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
    JOIN physionet-data.mimiciv_3_1_hosp.patients p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 36
),
-- Step 1b: Find admissions with diabetes
diabetes_adm AS (
  SELECT DISTINCT hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  WHERE
    ( (d.icd_version = 9 AND LEFT(d.icd_code,3) = '250')
      OR (d.icd_version = 10 AND LEFT(d.icd_code,3) IN ('E08','E09','E10','E11','E13')) )
),
-- Step 1c: Find admissions with acute heart failure
hf_adm AS (
  SELECT DISTINCT hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  WHERE
    ( (d.icd_version = 9 AND LEFT(d.icd_code,3) = '428')
      OR (d.icd_version = 10 AND LEFT(d.icd_code,4) IN ('I50.2','I50.3','I50.4')) )
),
-- Step 1d: Only admissions with both diabetes and acute HF
qualifying_admissions AS (
  SELECT ba.*
  FROM base_admissions ba
    JOIN diabetes_adm da ON ba.hadm_id = da.hadm_id
    JOIN hf_adm ha ON ba.hadm_id = ha.hadm_id
),
-- Step 2: Find GLP-1 injectable starts
glp1_drugs AS (
  SELECT DISTINCT LOWER(drug) AS drug_name
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions
  WHERE LOWER(drug) LIKE '%exenatide%'
     OR LOWER(drug) LIKE '%liraglutide%'
     OR LOWER(drug) LIKE '%dulaglutide%'
     OR LOWER(drug) LIKE '%semaglutide%'
     OR LOWER(drug) LIKE '%lixisenatide%'
     OR LOWER(drug) LIKE '%albiglutide%'
),
glp1_presc AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.route,
    pr.drug
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions pr
    JOIN glp1_drugs gd ON LOWER(pr.drug) = gd.drug_name
  WHERE
    LOWER(pr.route) LIKE '%sc%' OR LOWER(pr.route) LIKE '%subcut%'
),
-- Step 2b: For each qualifying admission, get earliest GLP-1 injectable start
first_glp1 AS (
  SELECT
    qa.subject_id,
    qa.hadm_id,
    qa.admittime,
    qa.dischtime,
    MIN(gp.starttime) AS glp1_starttime
  FROM qualifying_admissions qa
    JOIN glp1_presc gp ON qa.hadm_id = gp.hadm_id
  WHERE gp.starttime BETWEEN qa.admittime AND qa.dischtime
  GROUP BY qa.subject_id, qa.hadm_id, qa.admittime, qa.dischtime
),
-- Step 3: Classify GLP-1 start as first 24h or final 12h
classified AS (
  SELECT
    *,
    TIMESTAMP_DIFF(glp1_starttime, admittime, HOUR) AS hours_from_admit,
    TIMESTAMP_DIFF(dischtime, glp1_starttime, HOUR) AS hours_to_discharge,
    CASE WHEN TIMESTAMP_DIFF(glp1_starttime, admittime, HOUR) < 24 THEN 1 ELSE 0 END AS first_24h,
    CASE WHEN TIMESTAMP_DIFF(dischtime, glp1_starttime, HOUR) < 12 THEN 1 ELSE 0 END AS final_12h
  FROM first_glp1
)
-- Step 4: Calculate percentages
SELECT
  ROUND(100 * SUM(first_24h) / COUNT(*),1) AS percent_first_24h,
  ROUND(100 * SUM(final_12h) / COUNT(*),1) AS percent_final_12h
FROM classified;