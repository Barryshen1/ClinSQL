WITH acs_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 79 AND 89
    AND (
      (dx.icd_version = 9 AND (
         dx.icd_code LIKE '410%' OR  -- AMI
         dx.icd_code = '4111'        -- unstable angina
      ))
      OR
      (dx.icd_version = 10 AND (
         dx.icd_code LIKE 'I21%' OR  -- AMI
         dx.icd_code LIKE 'I22%' OR  -- subsequent MI
         dx.icd_code = 'I200'        -- unstable angina
      ))
    )
  GROUP BY adm.subject_id, adm.hadm_id
),
trop_t_labs AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
    ON le.itemid = di.itemid
  WHERE UPPER(di.label) LIKE '%TROPONIN T%'
    AND le.valuenum IS NOT NULL
),
first_trop AS (
  SELECT
    atl.subject_id,
    atl.hadm_id,
    atl.valuenum,
    ROW_NUMBER() OVER (PARTITION BY atl.hadm_id ORDER BY atl.charttime) AS rn
  FROM trop_t_labs atl
  JOIN acs_admissions aa
    ON atl.hadm_id = aa.hadm_id
)
SELECT
  CASE
    WHEN valuenum <= 0.04 THEN 'Normal'
    WHEN valuenum > 0.04 AND valuenum <= 0.1 THEN 'Borderline'
    WHEN valuenum > 0.1 THEN 'Elevated'
  END AS troponin_category,
  COUNT(DISTINCT hadm_id) AS admission_count
FROM first_trop
WHERE rn = 1
GROUP BY troponin_category
ORDER BY troponin_category;