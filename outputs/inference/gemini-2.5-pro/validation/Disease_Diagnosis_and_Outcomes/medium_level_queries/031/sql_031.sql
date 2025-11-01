WITH sepsis_admissions AS (
  SELECT
    adm.hadm_id,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS hospital_los_days,
    DATETIME_DIFF(adm.deathtime, adm.admittime, DAY) AS time_to_death_days,
    -- Hierarchical diagnosis grouping: Septic Shock takes precedence
    CASE
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
        WHERE dx.hadm_id = adm.hadm_id AND dx.icd_code IN ('78552', 'R6521')
      ) THEN 'Septic Shock'
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
        WHERE dx.hadm_id = adm.hadm_id
          AND (
               dx.icd_code IN ('99591', '99592') -- Sepsis/Severe Sepsis (ICD-9)
            OR dx.icd_code = 'R6520' -- Severe sepsis without septic shock (ICD-10)
            OR (dx.icd_version = 10 AND dx.icd_code LIKE 'A41%') -- Other Sepsis (ICD-10)
          )
      ) THEN 'Sepsis'
      ELSE NULL
    END AS diagnosis_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 53 AND 63
),

base_stats AS (
  SELECT
    diagnosis_group,
    CASE
      WHEN hospital_los_days <= 7 THEN 'LOS <= 7 days'
      ELSE 'LOS > 7 days'
    END AS los_group,
    COUNT(hadm_id) AS N,
    -- Calculate mortality rate for the group
    AVG(hospital_expire_flag) * 100.0 AS in_hospital_mortality_percent,
    -- Calculate median time to death for non-survivors only
    APPROX_QUANTILES(
      CASE WHEN hospital_expire_flag = 1 THEN time_to_death_days END, 100
    )[OFFSET(50)] AS median_time_to_death_days
  FROM
    sepsis_admissions
  WHERE
    diagnosis_group IS NOT NULL
  GROUP BY
    diagnosis_group,
    los_group
)

SELECT
  diagnosis_group,
  los_group,
  N,
  in_hospital_mortality_percent,
  median_time_to_death_days,
  -- Calculate absolute and relative differences for the LOS > 7 group, comparing to the LOS <= 7 group
  CASE
    WHEN los_group = 'LOS > 7 days'
    THEN
      in_hospital_mortality_percent - LAG(in_hospital_mortality_percent, 1, 0) OVER (PARTITION BY diagnosis_group ORDER BY los_group)
    ELSE NULL
  END AS absolute_mortality_difference_pp,
  CASE
    WHEN los_group = 'LOS > 7 days'
         AND LAG(in_hospital_mortality_percent, 1, 0) OVER (PARTITION BY diagnosis_group ORDER BY los_group) > 0
    THEN
      (in_hospital_mortality_percent - LAG(in_hospital_mortality_percent, 1, 0) OVER (PARTITION BY diagnosis_group ORDER BY los_group))
      / LAG(in_hospital_mortality_percent, 1, 0) OVER (PARTITION BY diagnosis_group ORDER BY los_group) * 100.0
    ELSE NULL
  END AS relative_mortality_difference_percent
FROM
  base_stats
ORDER BY
  diagnosis_group,
  los_group;