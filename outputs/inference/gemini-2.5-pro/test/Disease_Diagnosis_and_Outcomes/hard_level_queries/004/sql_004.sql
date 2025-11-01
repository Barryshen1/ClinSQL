WITH
  -- Step 1: Define the base cohort of female patients aged 44-54 with intracranial hemorrhage.
  base_cohort AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.hospital_expire_flag,
      DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    -- Filter for female patients aged 44-54 at the time of admission
    WHERE
      p.gender = 'F'
      AND (DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age) BETWEEN 44 AND 54
      -- Ensure the admission has a diagnosis of intracranial hemorrhage
      AND a.hadm_id IN (
        SELECT DISTINCT
          hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE
          (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('430', '431', '432'))
          OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
      )
  ),
  -- Step 2: Calculate the Charlson Comorbidity Index (CCI) as the composite risk score.
  -- First, map all ICD codes for the cohort to Charlson comorbidity categories.
  charlson_map AS (
    SELECT
      dx.hadm_id,
      CASE
        WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) IN ('410', '412')) OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) IN ('I21', 'I22')) THEN 'MI'
        WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) = '428') OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) IN ('I50', 'I099', 'I110', 'I130', 'I132', 'I255', 'I420', 'I425', 'I426', 'I427', 'I428', 'I429', 'I43', 'P290')) THEN 'CHF'
        WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) IN ('441', '557') OR SUBSTR(dx.icd_code, 1, 4) IN ('4439', '7854')) OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) IN ('I70', 'I71', 'I73') OR SUBSTR(dx.icd_code, 1, 4) = 'K551') THEN 'PVD'
        WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN '430' AND '438') OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN 'I60' AND 'I69') OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) = 'G45') THEN 'CVD'
        WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) = '290' OR SUBSTR(dx.icd_code, 1, 4) IN ('2941', '3312')) OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) IN ('F00','F01','F02','F03','G30') OR SUBSTR(dx.icd_code, 1, 4) = 'G311') THEN 'DEMENTIA'
        WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN '490' AND '508' AND SUBSTR(dx.icd_code, 1, 4) != '5070') OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN 'J40' AND 'J47') OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN 'J60' AND 'J67') THEN 'PULMONARY'
        WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 4) IN ('7100', '7101', '7104', '7140', '7142')) OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) IN ('M05', 'M06', 'M32', 'M33', 'M34')) THEN 'RHEUMATIC'
        WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN '531' AND '534') OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN 'K25' AND 'K28') THEN 'PUD'
        WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 4) IN ('5712', '5714', '5715', '5716')) OR (dx.icd_version = 10 AND (SUBSTR(dx.icd_code, 1, 3) IN ('B18', 'K73', 'K74') OR SUBSTR(dx.icd_code, 1, 4) IN ('K700', 'K703', 'K717'))) THEN 'MILD_LIVER'
        WHEN (dx.icd_version = 9 AND (SUBSTR(dx.icd_code, 1, 4) IN ('2500', '2501', '2502', '2503', '2507'))) OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) IN ('E10', 'E11', 'E12', 'E13', 'E14') AND SUBSTR(dx.icd_code, 5, 1) NOT IN ('.2','.3','.4','.5','.7')) THEN 'DIABETES'
        WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 4) IN ('2504', '2505', '2506')) OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) IN ('E10', 'E11', 'E12', 'E13', 'E14') AND SUBSTR(dx.icd_code, 5, 1) IN ('.2','.3','.4','.5','.7')) THEN 'DIABETES_COMP'
        WHEN (dx.icd_version = 9 AND (SUBSTR(dx.icd_code, 1, 3) = '342' OR SUBSTR(dx.icd_code, 1, 4) = '3441')) OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) IN ('G81', 'G82')) THEN 'PARAPLEGIA'
        WHEN (dx.icd_version = 9 AND (SUBSTR(dx.icd_code, 1, 3) IN ('582', '585', '586') OR SUBSTR(dx.icd_code, 1, 4) IN ('5830', '5831', '5832', '5833', '5834', '5835', '5836', '5837'))) OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) IN ('N18', 'N19')) THEN 'RENAL'
        WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN '140' AND '172') OR (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN '174' AND '195') OR (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN '200' AND '208') OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN 'C00' AND 'C76') OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN 'C81' AND 'C96') THEN 'CANCER'
        WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 4) IN ('5722', '5723', '5724')) OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 4) IN ('K721', 'K729', 'K766', 'K767')) THEN 'SEVERE_LIVER'
        WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN '196' AND '199') OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN 'C77' AND 'C80') THEN 'METS'
        WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) = '042') OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN 'B20' AND 'B24') THEN 'HIV'
        ELSE NULL
      END AS comorbidity
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    WHERE dx.hadm_id IN (SELECT hadm_id FROM base_cohort)
  ),
  -- Aggregate mapped comorbidities to get a final score for each admission
  charlson_scores AS (
    SELECT
      hadm_id,
      SUM(CASE
        WHEN comorbidity IN ('MI', 'CHF', 'PVD', 'CVD', 'DEMENTIA', 'PULMONARY', 'RHEUMATIC', 'PUD', 'MILD_LIVER', 'DIABETES') THEN 1
        WHEN comorbidity IN ('DIABETES_COMP', 'PARAPLEGIA', 'RENAL', 'CANCER') THEN 2
        WHEN comorbidity = 'SEVERE_LIVER' THEN 3
        WHEN comorbidity IN ('METS', 'HIV') THEN 6
        ELSE 0
      END) AS charlson_score
    FROM (SELECT DISTINCT hadm_id, comorbidity FROM charlson_map WHERE comorbidity IS NOT NULL)
    GROUP BY hadm_id
  ),
  -- Step 3: Identify admissions with cardiac or neurologic complications.
  complications AS (
    SELECT
      hadm_id,
      MAX(CASE
        WHEN
          (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) = '410' OR SUBSTR(icd_code, 1, 5) = '785.51' OR SUBSTR(icd_code, 1, 3) = '428' OR SUBSTR(icd_code, 1, 4) = '427.5'))
          OR (icd_version = 10 AND (SUBSTR(icd_code, 1, 3) = 'I21' OR SUBSTR(icd_code, 1, 4) = 'R57.0' OR SUBSTR(icd_code, 1, 3) = 'I50' OR SUBSTR(icd_code, 1, 3) = 'I46'))
        THEN 1 ELSE 0
      END) AS has_cardiac_complication,
      MAX(CASE
        WHEN
          (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) = '345' OR SUBSTR(icd_code, 1, 5) = '780.39' OR SUBSTR(icd_code, 1, 4) = '348.5' OR SUBSTR(icd_code, 1, 3) = '331'))
          OR (icd_version = 10 AND (SUBSTR(icd_code, 1, 3) = 'G40' OR SUBSTR(icd_code, 1, 4) = 'R56.9' OR SUBSTR(icd_code, 1, 4) = 'G93.6' OR SUBSTR(icd_code, 1, 3) = 'G91'))
        THEN 1 ELSE 0
      END) AS has_neuro_complication
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE hadm_id IN (SELECT hadm_id FROM base_cohort)
    GROUP BY hadm_id
  ),
  -- Step 4: Combine all data and assign quartiles based on risk score.
  cohort_with_quartiles AS (
    SELECT
      b.hadm_id,
      b.hospital_expire_flag,
      b.los,
      COALESCE(c.has_cardiac_complication, 0) AS has_cardiac_complication,
      COALESCE(c.has_neuro_complication, 0) AS has_neuro_complication,
      NTILE(4) OVER (ORDER BY COALESCE(cs.charlson_score, 0)) AS risk_quartile
    FROM base_cohort AS b
    LEFT JOIN charlson_scores AS cs
      ON b.hadm_id = cs.hadm_id
    LEFT JOIN complications AS c
      ON b.hadm_id = c.hadm_id
  )
-- Step 5: Final aggregation to report metrics per quartile.
SELECT
  risk_quartile,
  COUNT(hadm_id) AS patient_count,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
  AVG(has_cardiac_complication) AS cardiac_complication_rate,
  AVG(has_neuro_complication) AS neurologic_complication_rate,
  APPROX_QUANTILES(
    CASE WHEN hospital_expire_flag = 0 THEN los END, 100
  )[OFFSET(50)] AS median_los_survivors
FROM cohort_with_quartiles
GROUP BY
  risk_quartile
ORDER BY
  risk_quartile;