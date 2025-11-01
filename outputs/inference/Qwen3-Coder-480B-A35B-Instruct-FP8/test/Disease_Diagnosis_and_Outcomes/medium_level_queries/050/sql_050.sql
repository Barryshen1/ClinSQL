WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    a.hospital_expire_flag,
    i.los AS icu_los,
    CASE WHEN i.los <= 5 THEN '≤5' ELSE '>5' END AS los_group,
    MAX(CASE WHEN d_icd.long_title LIKE '%chronic kidney disease%' THEN 1 ELSE 0 END) OVER (PARTITION BY a.hadm_id) AS ckd,
    MAX(CASE WHEN d_icd.long_title LIKE '%diabetes%' THEN 1 ELSE 0 END) OVER (PARTITION BY a.hadm_id) AS diabetes,
    MAX(CASE WHEN d_icd.long_title LIKE '%atrial fibrillation%' THEN 1 ELSE 0 END) OVER (PARTITION BY a.hadm_id) AS afib,
    MAX(CASE WHEN d_icd.long_title LIKE '%hypertension%' THEN 1 ELSE 0 END) OVER (PARTITION BY a.hadm_id) AS hypertension
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON a.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON dx.icd_code = d_icd.icd_code AND dx.icd_version = d_icd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND (
      (dx.icd_version = 9 AND dx.icd_code IN ('99591'))
      OR
      (dx.icd_version = 10 AND dx.icd_code IN ('A419'))
    )
    AND NOT (
      (dx.icd_version = 9 AND dx.icd_code IN ('78552'))
      OR
      (dx.icd_version = 10 AND dx.icd_code IN ('R6521'))
    )
)

SELECT
  los_group,
  ckd,
  diabetes,
  afib,
  hypertension,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * 100, 2) AS mortality_percent
FROM
  cohort
GROUP BY
  los_group, ckd, diabetes, afib, hypertension
ORDER BY
  los_group, ckd, diabetes, afib, hypertension;