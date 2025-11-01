WITH sepsis_hadm AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%sepsis%'
    AND LOWER(dd.long_title) NOT LIKE '%septic shock%'
),

-- 2) Base cohort: male, age 75-85, LOS computable, within sepsis_hadm
base AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END AS death_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN sepsis_hadm AS s
    ON a.hadm_id = s.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.dischtime IS NOT NULL
),

-- 3) Comorbidity flags per hadm_id derived from long_title keywords
comorb AS (
  SELECT
    hadm_id,
    MAX(CASE
          WHEN LOWER(dd.long_title) LIKE '%chronic kidney disease%'
               OR LOWER(dd.long_title) LIKE '%kidney disease%'
               OR LOWER(dd.long_title) LIKE '%renal failure%'
          THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes mellitus%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%atrial fibrillation%'
             OR LOWER(dd.long_title) LIKE '%atrial flutter%' THEN 1 ELSE 0 END) AS has_afib,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%hypertension%' THEN 1 ELSE 0 END) AS has_htn
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  GROUP BY hadm_id
)

-- 4) Final aggregation: mortality by LOS group and presence/absence for each comorbidity
SELECT
  LOS_group,
  comorb,
  presence,
  AVG(CAST(death_flag AS FLOAT64)) AS mortality_rate
FROM (
  SELECT
    CASE WHEN b.los_days <= 5 THEN '<=5' ELSE '>5' END AS LOS_group,
    b.death_flag,
    comp_tmp.comorb,
    comp_tmp.presence
  FROM base AS b
  LEFT JOIN comorb AS c
    ON b.hadm_id = c.hadm_id
  CROSS JOIN UNNEST([
    STRUCT('CKD' AS comorb, COALESCE(c.has_ckd, 0) AS presence),
    STRUCT('Diabetes' AS comorb, COALESCE(c.has_diabetes, 0) AS presence),
    STRUCT('AFib' AS comorb, COALESCE(c.has_afib, 0) AS presence),
    STRUCT('Hypertension' AS comorb, COALESCE(c.has_htn, 0) AS presence)
  ]) AS comp_tmp
) AS t
GROUP BY LOS_group, comorb, presence
ORDER BY LOS_group, comorb, presence;