WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    MAX(CASE WHEN d_ckd.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN d_dm.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_ami
    ON a.subject_id = d_ami.subject_id AND a.hadm_id = d_ami.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_ckd
    ON a.subject_id = d_ckd.subject_id AND a.hadm_id = d_ckd.hadm_id
    AND d_ckd.icd_code LIKE 'N18%' AND d_ckd.icd_version = 10
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_dm
    ON a.subject_id = d_dm.subject_id AND a.hadm_id = d_dm.hadm_id
    AND d_dm.icd_code LIKE 'E1%' AND d_dm.icd_version = 10
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
    AND d_ami.icd_code LIKE 'I21%' AND d_ami.icd_version = 10
    AND a.hadm_id NOT IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE (icd_code LIKE 'R57%' OR icd_code LIKE 'J96%') AND icd_version = 10
    )
  GROUP BY p.subject_id, a.hadm_id, a.hospital_expire_flag, a.admittime, a.dischtime
),
cohort_groups AS (
  SELECT
    CASE WHEN los <= 5 THEN 'LOS ≤5' ELSE 'LOS >5' END AS los_group,
    COUNT(*) AS n_patients,
    SUM(has_ckd) AS n_ckd,
    SUM(has_diabetes) AS n_diabetes,
    SUM(hospital_expire_flag) AS n_died
  FROM cohort
  GROUP BY los_group
),
mortality AS (
  SELECT
    los_group,
    n_patients,
    n_ckd,
    n_diabetes,
    n_died,
    n_died / n_patients AS mortality_rate
  FROM cohort_groups
),
diff AS (
  SELECT
    MAX(CASE WHEN los_group = 'LOS >5' THEN mortality_rate END) - 
    MAX(CASE WHEN los_group = 'LOS ≤5' THEN mortality_rate END) AS absolute_difference,
    (MAX(CASE WHEN los_group = 'LOS >5' THEN mortality_rate END) - 
     MAX(CASE WHEN los_group = 'LOS ≤5' THEN mortality_rate END)) /
    NULLIF(MAX(CASE WHEN los_group = 'LOS ≤5' THEN mortality_rate END), 0) AS relative_difference
  FROM mortality
)
SELECT
  m.los_group,
  m.n_patients,
  m.n_died,
  ROUND(m.mortality_rate * 100, 2) AS mortality_rate_percent,
  ROUND(m.n_ckd * 100.0 / m.n_patients, 2) AS ckd_prevalence_percent,
  ROUND(m.n_diabetes * 100.0 / m.n_patients, 2) AS diabetes_prevalence_percent,
  ROUND(d.absolute_difference * 100, 2) AS absolute_difference_percent,
  ROUND(d.relative_difference * 100, 2) AS relative_difference_percent
FROM mortality m
CROSS JOIN diff d
ORDER BY m.los_group;