WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.los,
    CASE WHEN i.los <= 7 THEN 'LOS <=7' ELSE 'LOS >7' END AS los_group,
    CASE
      WHEN DATETIME_DIFF(i.intime, a.admittime, HOUR) <= 24 THEN 'Day-1 ICU'
      ELSE 'Not Day-1 ICU'
    END AS day1_icu_status,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND dd.icd_code IN ('I5023', 'I5033') -- ADHF codes
    )
),

comorbidities AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN dd.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN dd.icd_code LIKE 'E10%' OR dd.icd_code LIKE 'E11%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    d.hadm_id IN (SELECT hadm_id FROM cohort)
  GROUP BY
    hadm_id
),

final_cohort AS (
  SELECT
    c.*,
    COALESCE(cm.has_ckd, 0) AS has_ckd,
    COALESCE(cm.has_diabetes, 0) AS has_diabetes
  FROM
    cohort c
  LEFT JOIN
    comorbidities cm
    ON c.hadm_id = cm.hadm_id
)

SELECT
  los_group,
  day1_icu_status,
  COUNT(*) AS n_patients,
  AVG(hospital_expire_flag) * 100 AS in_hosp_mortality_pct,
  AVG(has_ckd) * 100 AS ckd_prevalence_pct,
  AVG(has_diabetes) * 100 AS diabetes_prevalence_pct
FROM
  final_cohort
GROUP BY
  los_group,
  day1_icu_status
ORDER BY
  los_group,
  day1_icu_status;