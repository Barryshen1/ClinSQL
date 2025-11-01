WITH
  -- Step 1: Identify female inpatients aged 85-95 with an asthma diagnosis
  asthma_admissions AS (
    SELECT
      pat.subject_id,
      adm.hadm_id,
      adm.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON pat.subject_id = adm.subject_id
    WHERE
      pat.gender = 'F'
      AND (
        EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age
      ) BETWEEN 85 AND 95
      AND EXISTS (
        SELECT
          1
        FROM
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        WHERE
          dx.hadm_id = adm.hadm_id
          AND (
            (dx.icd_version = 9 AND dx.icd_code LIKE '493%') -- ICD-9 Asthma
            OR (dx.icd_version = 10 AND dx.icd_code LIKE 'J45%') -- ICD-10 Asthma
          )
      )
  ),
  -- Step 2: Calculate a comorbidity score for each admission
  -- This is a count of distinct diagnoses, excluding the primary asthma diagnosis
  comorbidity_scores AS (
    SELECT
      aa.hadm_id,
      COUNT(DISTINCT dx.icd_code) AS comorbidity_score
    FROM
      asthma_admissions AS aa
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON aa.hadm_id = dx.hadm_id AND NOT (
        (dx.icd_version = 9 AND dx.icd_code LIKE '493%')
        OR (dx.icd_version = 10 AND dx.icd_code LIKE 'J45%')
      )
    GROUP BY
      aa.hadm_id
  ),
  -- Step 3: Flag admissions with cardiovascular or neurologic complications
  complications AS (
    SELECT
      aa.hadm_id,
      -- Flag for cardiovascular complications
      MAX(
        CASE
          WHEN
            (
              dx.icd_version = 9 AND (
                dx.icd_code LIKE '410%' -- Acute MI
                OR dx.icd_code LIKE '428%' -- Heart Failure
                OR SUBSTR(dx.icd_code, 1, 3) IN ('430', '431', '432', '433', '434') -- Stroke
                OR dx.icd_code LIKE '436%' -- Acute, ill-defined CVA
                OR dx.icd_code LIKE '4151%' -- Pulmonary Embolism
                OR dx.icd_code = '42731' -- Atrial Fibrillation
              )
            )
            OR (
              dx.icd_version = 10 AND (
                dx.icd_code LIKE 'I21%' OR dx.icd_code LIKE 'I22%' -- MI
                OR dx.icd_code LIKE 'I50%' -- Heart Failure
                OR SUBSTR(dx.icd_code, 1, 3) BETWEEN 'I60' AND 'I64' -- Stroke
                OR dx.icd_code LIKE 'I26%' -- Pulmonary Embolism
                OR dx.icd_code LIKE 'I48%' -- Atrial Fibrillation/Flutter
              )
            )
            THEN 1
          ELSE 0
        END
      ) AS has_cardiovascular_comp,
      -- Flag for neurologic complications
      MAX(
        CASE
          WHEN
            (
              dx.icd_version = 9 AND (
                SUBSTR(dx.icd_code, 1, 3) IN ('430', '431', '432', '433', '434') -- Stroke
                OR dx.icd_code LIKE '436%' -- Acute, ill-defined CVA
                OR dx.icd_code LIKE '3483%' -- Encephalopathy
                OR dx.icd_code IN ('2930', '2931') -- Delirium
                OR dx.icd_code = '78009' -- Other alteration of consciousness
                OR dx.icd_code LIKE '345%' -- Epilepsy
                OR dx.icd_code = '78039' -- Other convulsions
              )
            )
            OR (
              dx.icd_version = 10 AND (
                SUBSTR(dx.icd_code, 1, 3) BETWEEN 'I60' AND 'I64' -- Stroke
                OR dx.icd_code LIKE 'G934%' -- Encephalopathy
                OR dx.icd_code LIKE 'F05%' -- Delirium
                OR dx.icd_code = 'R410' -- Disorientation, unspecified
                OR dx.icd_code LIKE 'G40%' -- Epilepsy
                OR dx.icd_code LIKE 'R56%' -- Convulsions
              )
            )
            THEN 1
          ELSE 0
        END
      ) AS has_neurologic_comp
    FROM
      asthma_admissions AS aa
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON aa.hadm_id = dx.hadm_id
    GROUP BY
      aa.hadm_id
  ),
  -- Step 4: Combine all data and rank patients into quartiles based on comorbidity score
  ranked_cohort AS (
    SELECT
      aa.hadm_id,
      aa.hospital_expire_flag,
      COALESCE(cp.has_cardiovascular_comp, 0) AS has_cardiovascular_comp,
      COALESCE(cp.has_neurologic_comp, 0) AS has_neurologic_comp,
      NTILE(4) OVER (ORDER BY COALESCE(cs.comorbidity_score, 0)) AS score_quartile
    FROM
      asthma_admissions AS aa
    LEFT JOIN
      comorbidity_scores AS cs
      ON aa.hadm_id = cs.hadm_id
    LEFT JOIN
      complications AS cp
      ON aa.hadm_id = cp.hadm_id
  )
-- Final Step: Aggregate outcomes by comorbidity quartile
SELECT
  score_quartile,
  COUNT(hadm_id) AS number_of_patients,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_rate,
  ROUND(AVG(has_cardiovascular_comp) * 100, 2) AS cardiovascular_complication_rate,
  ROUND(AVG(has_neurologic_comp) * 100, 2) AS neurologic_complication_rate
FROM
  ranked_cohort
GROUP BY
  score_quartile
ORDER BY
  score_quartile;