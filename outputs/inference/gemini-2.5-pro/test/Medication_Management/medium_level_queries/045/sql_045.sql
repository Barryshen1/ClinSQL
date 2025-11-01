WITH
  -- Step 1: Identify all hospital admissions with a diabetes diagnosis
  diabetes_hadms AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      icd_code LIKE '250%' -- ICD-9
      OR icd_code LIKE 'E08%' -- ICD-10
      OR icd_code LIKE 'E09%' -- ICD-10
      OR icd_code LIKE 'E10%' -- ICD-10
      OR icd_code LIKE 'E11%' -- ICD-10
      OR icd_code LIKE 'E13%' -- ICD-10
  ),
  -- Step 2: Identify all hospital admissions with a heart failure diagnosis
  hf_hadms AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      icd_code LIKE '428%' -- ICD-9
      OR icd_code LIKE 'I50%' -- ICD-10
  ),
  -- Step 3: Define the main cohort: Female patients, 54-64 years old, with both conditions
  cohort AS (
    SELECT
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN diabetes_hadms AS dh
      ON adm.hadm_id = dh.hadm_id
    INNER JOIN hf_hadms AS hfh
      ON adm.hadm_id = hfh.hadm_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 54 AND 64
  ),
  -- Step 4: Classify relevant prescriptions as 'Insulin' or 'Oral Agent'
  med_classifications AS (
    SELECT
      hadm_id,
      starttime,
      CASE
        WHEN LOWER(drug) LIKE '%insulin%'
          THEN 'Insulin'
        WHEN
          LOWER(drug) LIKE '%metformin%'
          OR LOWER(drug) LIKE '%glipizide%'
          OR LOWER(drug) LIKE '%glyburide%'
          OR LOWER(drug) LIKE '%glimepiride%'
          OR LOWER(drug) LIKE '%pioglitazone%'
          OR LOWER(drug) LIKE '%rosiglitazone%'
          OR LOWER(drug) LIKE '%sitagliptin%'
          OR LOWER(drug) LIKE '%saxagliptin%'
          OR LOWER(drug) LIKE '%linagliptin%'
          OR LOWER(drug) LIKE '%alogliptin%'
          OR LOWER(drug) LIKE '%canagliflozin%'
          OR LOWER(drug) LIKE '%dapagliflozin%'
          OR LOWER(drug) LIKE '%empagliflozin%'
          OR LOWER(drug) LIKE '%repaglinide%'
          OR LOWER(drug) LIKE '%nateglinide%'
          OR LOWER(drug) LIKE '%acarbose%'
          OR LOWER(drug) LIKE '%miglitol%'
          THEN 'Oral Agent'
        ELSE NULL
      END AS med_category
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  ),
  -- Step 5: For each admission, flag if a medication was started in the defined time windows
  hadm_flags AS (
    SELECT
      c.hadm_id,
      MAX(
        CASE
          WHEN mc.med_category = 'Insulin' AND mc.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
            THEN 1
          ELSE 0
        END
      ) AS on_insulin_first_12h,
      MAX(
        CASE
          WHEN mc.med_category = 'Oral Agent' AND mc.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
            THEN 1
          ELSE 0
        END
      ) AS on_oral_first_12h,
      MAX(
        CASE
          WHEN mc.med_category = 'Insulin' AND mc.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
            THEN 1
          ELSE 0
        END
      ) AS on_insulin_final_48h,
      MAX(
        CASE
          WHEN mc.med_category = 'Oral Agent' AND mc.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
            THEN 1
          ELSE 0
        END
      ) AS on_oral_final_48h
    FROM cohort AS c
    LEFT JOIN med_classifications AS mc
      ON c.hadm_id = mc.hadm_id
    GROUP BY
      c.hadm_id
  )
-- Step 6: Calculate final prevalence and net change statistics
SELECT
  ROUND(AVG(on_insulin_first_12h) * 100, 2) AS insulin_prevalence_first_12h,
  ROUND(AVG(on_oral_first_12h) * 100, 2) AS oral_agent_prevalence_first_12h,
  ROUND(AVG(on_insulin_final_48h) * 100, 2) AS insulin_prevalence_final_48h,
  ROUND(AVG(on_oral_final_48h) * 100, 2) AS oral_agent_prevalence_final_48h,
  ROUND((AVG(on_insulin_final_48h) - AVG(on_insulin_first_12h)) * 100, 2) AS insulin_net_change_pp,
  ROUND((AVG(on_oral_final_48h) - AVG(on_oral_first_12h)) * 100, 2) AS oral_agent_net_change_pp
FROM hadm_flags;