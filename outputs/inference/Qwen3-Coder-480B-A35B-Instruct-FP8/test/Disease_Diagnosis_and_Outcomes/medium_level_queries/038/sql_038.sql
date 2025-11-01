WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
),
comorbidities AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%chronic kidney disease%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  GROUP BY
    hadm_id
)
SELECT
  c.icu_status,
  CASE WHEN c.los_days < 8 THEN '<8 days' ELSE '≥8 days' END AS los_group,
  COUNT(*) AS total_admissions,
  AVG(CAST(c.hospital_expire_flag AS FLOAT64)) * 100 AS in_hospital_mortality_pct,
  AVG(COALESCE(cm.has_ckd, 0)) * 100 AS ckd_prevalence_pct,
  AVG(COALESCE(cm.has_diabetes, 0)) * 100 AS diabetes_prevalence_pct
FROM
  cohort c
LEFT JOIN
  comorbidities cm
  ON c.hadm_id = cm.hadm_id
GROUP BY
  c.icu_status,
  los_group
ORDER BY
  c.icu_status,
  los_group;