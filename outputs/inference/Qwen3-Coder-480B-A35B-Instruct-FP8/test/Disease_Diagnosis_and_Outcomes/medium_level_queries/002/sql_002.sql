WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    p.anchor_age,
    p.gender,
    MAX(CASE WHEN did.long_title LIKE '%Chronic kidney disease%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN did.long_title LIKE '%Diabetes%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE
    p.anchor_age BETWEEN 62 AND 72
    AND p.gender = 'F'
    AND di.seq_num = 1
    AND did.icd_code LIKE 'I21%' -- AMI
    AND a.hadm_id NOT IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did2
        ON di2.icd_code = did2.icd_code AND di2.icd_version = did2.icd_version
      WHERE
        did2.icd_code IN ('R578', 'J960') OR
        did2.long_title LIKE '%shock%' OR
        did2.long_title LIKE '%respiratory failure%'
    )
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.anchor_age, p.gender
),

grouped_stats AS (
  SELECT
    CASE WHEN los <= 5 THEN 'LOS <= 5' ELSE 'LOS > 5' END AS los_group,
    COUNT(*) AS n_patients,
    SUM(hospital_expire_flag) AS deaths,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(has_ckd) AS ckd_prevalence,
    AVG(has_diabetes) AS diabetes_prevalence
  FROM cohort
  GROUP BY los_group
)

SELECT
  los_group,
  n_patients,
  deaths,
  mortality_rate,
  ckd_prevalence,
  diabetes_prevalence,
  -- Absolute mortality difference
  ABS(
    FIRST_VALUE(mortality_rate) OVER (ORDER BY los_group)
    - LAST_VALUE(mortality_rate) OVER (ORDER BY los_group ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
  ) AS abs_mortality_diff,
  -- Relative mortality difference
  SAFE_DIVIDE(
    FIRST_VALUE(mortality_rate) OVER (ORDER BY los_group)
    - LAST_VALUE(mortality_rate) OVER (ORDER BY los_group ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING),
    LAST_VALUE(mortality_rate) OVER (ORDER BY los_group ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
  ) AS rel_mortality_diff
FROM grouped_stats
ORDER BY los_group;