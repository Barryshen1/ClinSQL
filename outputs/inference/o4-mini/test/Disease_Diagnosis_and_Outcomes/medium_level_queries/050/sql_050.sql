WITH sepsis_adm AS (
  -- Identify admissions with sepsis (excluding septic shock)
  SELECT DISTINCT
    di.subject_id,
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code
     AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%sepsis%'
    AND LOWER(d.long_title) NOT LIKE '%septic shock%'
),
base_cohort AS (
  -- Filter to male patients age 75–85 with a sepsis admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Compute hospital LOS in days and bin
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 5 THEN '<=5'
      ELSE '>5'
    END AS los_bin
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN sepsis_adm s
      ON a.subject_id = s.subject_id
     AND a.hadm_id   = s.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
),
comorbidity_flags AS (
  -- For each admission, pull all ICD diagnoses to flag comorbidities
  SELECT
    b.subject_id,
    b.hadm_id,
    b.los_bin,
    b.hospital_expire_flag,
    -- Flags for each comorbidity
    MAX(CASE
          WHEN dd.icd_version = 10
           AND (STARTS_WITH(dd.icd_code, 'N18') OR STARTS_WITH(dd.icd_code, 'N19'))
          THEN 1 ELSE 0
        END) AS ckd_flag,
    MAX(CASE
          WHEN dd.icd_version = 10
           AND (STARTS_WITH(dd.icd_code, 'E10')
             OR STARTS_WITH(dd.icd_code, 'E11')
             OR STARTS_WITH(dd.icd_code, 'E13')
             OR STARTS_WITH(dd.icd_code, 'E14'))
          THEN 1 ELSE 0
        END) AS diabetes_flag,
    MAX(CASE
          WHEN dd.icd_version = 10
           AND STARTS_WITH(dd.icd_code, 'I48')
          THEN 1 ELSE 0
        END) AS afib_flag,
    MAX(CASE
          WHEN dd.icd_version = 10
           AND (STARTS_WITH(dd.icd_code, 'I10')
             OR STARTS_WITH(dd.icd_code, 'I11')
             OR STARTS_WITH(dd.icd_code, 'I15'))
          THEN 1 ELSE 0
        END) AS htn_flag
  FROM
    base_cohort b
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dd
      ON b.hadm_id = dd.hadm_id
  GROUP BY
    b.subject_id,
    b.hadm_id,
    b.los_bin,
    b.hospital_expire_flag
)
-- Final aggregation: stratify by LOS bin and all four comorbidity flags
SELECT
  los_bin,
  ckd_flag AS ckd,
  diabetes_flag AS diabetes,
  afib_flag AS afib,
  htn_flag AS hypertension,
  COUNT(*) AS admissions_n,
  SUM(hospital_expire_flag) AS deaths_n,
  ROUND(
    100.0 * SUM(hospital_expire_flag) / COUNT(*),
    2
  ) AS mortality_pct
FROM
  comorbidity_flags
GROUP BY
  los_bin,
  ckd_flag,
  diabetes_flag,
  afib_flag,
  htn_flag
ORDER BY
  los_bin,
  ckd_flag DESC,
  diabetes_flag DESC,
  afib_flag DESC,
  htn_flag DESC;