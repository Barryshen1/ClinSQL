WITH female_35_45 AS (
  SELECT subject_id, gender, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 35 AND 45
),

first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN female_35_45 p ON p.subject_id = a.subject_id
),

first_adm_filtered AS (
  -- keep only the first admission per subject
  SELECT subject_id, hadm_id, admittime, hospital_expire_flag
  FROM first_admissions
  WHERE rn = 1
),

cabg_procedures AS (
  -- identify CABG procedures via description and common ICD patterns
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.icd_code,
    pr.icd_version,
    dp.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code
   AND pr.icd_version = dp.icd_version
  WHERE
    (
      -- textual match for "coronary" and "bypass" in the procedure description
      (LOWER(COALESCE(dp.long_title, '')) LIKE '%coronary%' AND LOWER(COALESCE(dp.long_title, '')) LIKE '%bypass%')
      -- OR common ICD-9 procedure code prefix for CABG
      OR (pr.icd_version = 9 AND pr.icd_code LIKE '36.1%')
      -- OR common ICD-10-PCS prefix for CABG procedures (most CABG ICD-10-PCS start with '0210')
      OR (pr.icd_version = 10 AND pr.icd_code LIKE '0210%')
    )
)

SELECT
  COUNT(DISTINCT fa.subject_id) AS total_patients_first_admission_with_cabg,
  SUM(fa.hospital_expire_flag) AS inhospital_deaths,
  SAFE_DIVIDE(SUM(fa.hospital_expire_flag), COUNT(DISTINCT fa.subject_id)) AS inhospital_mortality_rate
FROM first_adm_filtered fa
JOIN cabg_procedures cp
  ON cp.hadm_id = fa.hadm_id
;