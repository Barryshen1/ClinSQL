WITH sepsis_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los AS icu_los,
    CASE WHEN i.los <= 5 THEN 'LOS <=5' ELSE 'LOS >5' END AS los_group,
    CASE
      WHEN i.intime <= DATETIME_ADD(a.admittime, INTERVAL 1 DAY) THEN 'ICU Day 1'
      ELSE 'Not ICU Day 1'
    END AS icu_day1_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND (
      (d.icd_version = 9 AND d.icd_code = '99591') OR
      (d.icd_version = 10 AND d.icd_code = 'A419')
    )
    -- Exclude septic shock
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd2
        ON d2.icd_code = dd2.icd_code AND d2.icd_version = dd2.icd_version
      WHERE d2.hadm_id = a.hadm_id
        AND (
          (d2.icd_version = 9 AND d2.icd_code = '78552') OR
          (d2.icd_version = 10 AND d2.icd_code = 'R572')
        )
    )
),

comorbidities AS (
  SELECT DISTINCT
    d.hadm_id,
    MAX(CASE WHEN (
      (d.icd_version = 9 AND d.icd_code IN ('5853', '5854', '5855', '5856')) OR
      (d.icd_version = 10 AND d.icd_code IN ('N183', 'N184', 'N185', 'N186'))
    ) THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN (
      (d.icd_version = 9 AND d.icd_code IN ('25000', '25001', '25002', '25003')) OR
      (d.icd_version = 10 AND d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%')
    ) THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY
    d.hadm_id
)

SELECT
  s.los_group,
  s.icu_day1_flag,
  COUNT(DISTINCT s.subject_id) AS N,
  ROUND(AVG(s.hospital_expire_flag) * 100, 2) AS mortality_percent,
  ROUND(AVG(COALESCE(c.has_ckd, 0)) * 100, 2) AS ckd_prevalence_percent,
  ROUND(AVG(COALESCE(c.has_diabetes, 0)) * 100, 2) AS diabetes_prevalence_percent
FROM
  sepsis_cohort s
LEFT JOIN
  comorbidities c
  ON s.hadm_id = c.hadm_id
GROUP BY
  s.los_group,
  s.icu_day1_flag
ORDER BY
  s.los_group,
  s.icu_day1_flag;