WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),
diagnosis_flags AS (
  SELECT
    di.hadm_id,
    MAX(CASE
      WHEN (di.icd_version = 9 AND di.icd_code LIKE '585%')
        OR (di.icd_version = 10 AND di.icd_code LIKE 'N18%')
      THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE
      WHEN (di.icd_version = 9 AND di.icd_code LIKE '250%')
        OR (di.icd_version = 10 AND di.icd_code LIKE 'E1%')
      THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  GROUP BY
    di.hadm_id
)
SELECT
  CASE
    WHEN pa.los_days < 8 THEN '<8'
    ELSE '>=8'
  END AS los_group,
  AVG(pa.hospital_expire_flag) * 100 AS in_hospital_mortality_pct,
  AVG(df.has_ckd) * 100 AS ckd_prevalence_pct,
  AVG(df.has_diabetes) * 100 AS diabetes_prevalence_pct,
  COUNT(*) AS total_admissions
FROM
  patient_admissions pa
LEFT JOIN
  diagnosis_flags df
  ON pa.hadm_id = df.hadm_id
GROUP BY
  los_group
ORDER BY
  los_group;