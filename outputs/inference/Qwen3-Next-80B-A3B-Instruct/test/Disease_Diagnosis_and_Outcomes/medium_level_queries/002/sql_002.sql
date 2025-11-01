WITH cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
    AND LOWER(d_icd.long_title) LIKE '%acute myocardial infarction%'
    AND a.hadm_id IS NOT NULL
),

cohort_excluded AS (
  SELECT c.*
  FROM cohort c
  WHERE NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
      ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
    WHERE d.hadm_id = c.hadm_id
      AND (
        LOWER(d_icd.long_title) LIKE '%shock%'
        OR LOWER(d_icd.long_title) LIKE '%respiratory failure%'
      )
  )
),

comorbidities AS (
  SELECT
    c.hadm_id,
    MAX(CASE WHEN LOWER(d_icd.long_title) LIKE '%chronic kidney disease%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN LOWER(d_icd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM cohort_excluded c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  GROUP BY c.hadm_id
),

final_cohort AS (
  SELECT
    c.hadm_id,
    c.hospital_expire_flag,
    c.los_days,
    CASE
      WHEN c.los_days <= 5 THEN 'LOS <= 5'
      WHEN c.los_days > 5 THEN 'LOS > 5'
    END AS los_group,
    co.has_ckd,
    co.has_diabetes
  FROM cohort_excluded c
  INNER JOIN comorbidities co ON c.hadm_id = co.hadm_id
),

grouped AS (
  SELECT
    los_group,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(has_ckd) AS ckd_prevalence,
    AVG(has_diabetes) AS diabetes_prevalence
  FROM final_cohort
  GROUP BY los_group
),

diffs AS (
  SELECT
    MAX(CASE WHEN los_group = 'LOS > 5' THEN mortality_rate END) - 
    MAX(CASE WHEN los_group = 'LOS <= 5' THEN mortality_rate END) AS abs_mortality_diff,
    MAX(CASE WHEN los_group = 'LOS > 5' THEN mortality_rate END) / 
    MAX(CASE WHEN los_group = 'LOS <= 5' THEN mortality_rate END) AS rel_mortality_diff
  FROM grouped
)

SELECT
  g.los_group,
  g.mortality_rate,
  g.ckd_prevalence,
  g.diabetes_prevalence,
  d.abs_mortality_diff,
  d.rel_mortality_diff
FROM grouped g
CROSS JOIN diffs d
ORDER BY g.los_group;