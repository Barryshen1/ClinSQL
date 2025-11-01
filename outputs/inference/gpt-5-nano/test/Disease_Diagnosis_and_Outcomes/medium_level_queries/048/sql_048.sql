WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    -- Heart failure during this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '428%') OR
          (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
        )
    )
)
SELECT
  CASE WHEN los_days < 8 THEN '<8 days' ELSE '>=8 days' END AS los_group,
  COUNT(*) AS n_admissions,
  100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality_percent,
  100.0 * SUM(CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di_ck
      WHERE di_ck.subject_id = base.subject_id
        AND di_ck.hadm_id = base.hadm_id
        AND (
          (di_ck.icd_version = 9 AND di_ck.icd_code LIKE '585%') OR
          (di_ck.icd_version = 10 AND di_ck.icd_code LIKE 'N18%')
        )
    ) THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS ckd_prevalence_percent,
  100.0 * SUM(CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di_diab
      WHERE di_diab.subject_id = base.subject_id
        AND di_diab.hadm_id = base.hadm_id
        AND (
          (di_diab.icd_version = 9 AND di_diab.icd_code LIKE '250%') OR
          (di_diab.icd_version = 10 AND di_diab.icd_code LIKE 'E1%')
        )
    ) THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS diabetes_prevalence_percent
FROM base
GROUP BY los_group
ORDER BY los_group;