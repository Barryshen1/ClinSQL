WITH admissions_with_los AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),
diabetes_flags AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.hadm_id
),
ckd_flags AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN d.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.hadm_id
)
SELECT
  CASE WHEN a.los_days < 8 THEN '<8' ELSE '>=8' END AS los_group,
  AVG(a.hospital_expire_flag) * 100 AS mortality_rate,
  AVG(COALESCE(df.has_diabetes, 0)) * 100 AS diabetes_prevalence,
  AVG(COALESCE(ckd.has_ckd, 0)) * 100 AS ckd_prevalence
FROM admissions_with_los a
LEFT JOIN diabetes_flags df ON a.hadm_id = df.hadm_id
LEFT JOIN ckd_flags ckd ON a.hadm_id = ckd.hadm_id
GROUP BY los_group;