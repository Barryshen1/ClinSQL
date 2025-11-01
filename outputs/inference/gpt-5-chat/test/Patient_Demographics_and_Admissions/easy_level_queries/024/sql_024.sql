WITH first_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN (
    SELECT subject_id, hadm_id, admittime, hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    QUALIFY ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) = 1
  ) a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 35 AND 45
),
cabbg_patients AS (
  SELECT DISTINCT fa.subject_id, fa.hadm_id, fa.hospital_expire_flag
  FROM first_admissions fa
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON fa.subject_id = pr.subject_id AND fa.hadm_id = pr.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code AND pr.icd_version = dpr.icd_version
  WHERE LOWER(dpr.long_title) LIKE '%coronary%'
    AND LOWER(dpr.long_title) LIKE '%bypass%'
)
SELECT
  COUNT(*) AS n_patients,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
  SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS mortality_rate
FROM cabbg_patients;