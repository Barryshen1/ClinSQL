WITH cohort AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.los,
    adm.hospital_expire_flag,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    pat.gender,
    pat.anchor_age,
    diag.icd_code,
    diag.icd_version,
    dicd.long_title,
    CASE
      WHEN icu.los <= 7 THEN 'LOS <= 7'
      ELSE 'LOS > 7'
    END AS los_group,
    CASE
      WHEN LOWER(dicd.long_title) LIKE '%septic shock%' THEN 'Septic Shock'
      WHEN LOWER(dicd.long_title) LIKE '%sepsis%' THEN 'Sepsis'
      ELSE NULL
    END AS diagnosis_group
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON icu.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON diag.icd_code = dicd.icd_code
    AND diag.icd_version = dicd.icd_version
  WHERE
    pat.anchor_age BETWEEN 53 AND 63
    AND pat.gender = 'F'
    AND LOWER(dicd.long_title) LIKE '%sepsis%'
),

filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE diagnosis_group IN ('Sepsis', 'Septic Shock')
),

grouped_stats AS (
  SELECT
    diagnosis_group,
    los_group,
    COUNT(*) AS n,
    AVG(hospital_expire_flag) * 100 AS mortality_percent,
    APPROX_QUANTILES(
      CASE WHEN hospital_expire_flag = 1 THEN TIMESTAMP_DIFF(deathtime, admittime, HOUR) ELSE NULL END,
      2
    )[OFFSET(1)] AS median_time_to_death_hours
  FROM
    filtered_cohort
  GROUP BY
    diagnosis_group, los_group
),

pivoted AS (
  SELECT
    diagnosis_group,
    MAX(CASE WHEN los_group = 'LOS <= 7' THEN n ELSE NULL END) AS n_los_le_7,
    MAX(CASE WHEN los_group = 'LOS > 7' THEN n ELSE NULL END) AS n_los_gt_7,
    MAX(CASE WHEN los_group = 'LOS <= 7' THEN mortality_percent ELSE NULL END) AS mortality_los_le_7,
    MAX(CASE WHEN los_group = 'LOS > 7' THEN mortality_percent ELSE NULL END) AS mortality_los_gt_7,
    MAX(CASE WHEN los_group = 'LOS <= 7' THEN median_time_to_death_hours ELSE NULL END) AS median_time_to_death_los_le_7,
    MAX(CASE WHEN los_group = 'LOS > 7' THEN median_time_to_death_hours ELSE NULL END) AS median_time_to_death_los_gt_7
  FROM
    grouped_stats
  GROUP BY
    diagnosis_group
)

SELECT
  diagnosis_group,
  n_los_le_7,
  n_los_gt_7,
  mortality_los_le_7,
  mortality_los_gt_7,
  median_time_to_death_los_le_7,
  median_time_to_death_los_gt_7,
  (mortality_los_gt_7 - mortality_los_le_7) AS abs_mortality_diff,
  CASE
    WHEN mortality_los_le_7 = 0 THEN NULL
    ELSE (mortality_los_gt_7 - mortality_los_le_7) / mortality_los_le_7
  END AS rel_mortality_diff
FROM
  pivoted
ORDER BY
  diagnosis_group;