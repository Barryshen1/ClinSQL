WITH diag_flags AS (
  -- Aggregate diagnosis text per hospital admission to produce flags for sepsis (excluding septic shock)
  -- and the specified comorbidities.
  SELECT
    d.hadm_id,
    MAX(CASE WHEN LOWER(di.long_title) LIKE '%sepsis%' AND LOWER(di.long_title) NOT LIKE '%septic shock%' THEN 1 ELSE 0 END) AS has_sepsis_noshock,
    MAX(CASE WHEN LOWER(di.long_title) LIKE '%septic shock%' THEN 1 ELSE 0 END) AS has_septic_shock,
    MAX(CASE WHEN LOWER(di.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN LOWER(di.long_title) LIKE '%atrial fibrillation%' THEN 1 ELSE 0 END) AS has_afib,
    MAX(CASE WHEN LOWER(di.long_title) LIKE '%hypertension%' THEN 1 ELSE 0 END) AS has_htn,
    MAX(CASE WHEN
          LOWER(di.long_title) LIKE '%chronic kidney%'
          OR LOWER(di.long_title) LIKE '%chronic renal%'
          OR LOWER(di.long_title) LIKE '%renal failure, chronic%'
          OR LOWER(di.long_title) LIKE '%end stage renal%'
          OR LOWER(di.long_title) LIKE '%ckd%'
        THEN 1 ELSE 0 END) AS has_ckd
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  GROUP BY
    d.hadm_id
),

cohort AS (
  -- Join admissions/patients with the diagnosis flags and apply inclusion/exclusion criteria.
  SELECT
    a.hadm_id,
    a.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    -- LOS in days (integer)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 5 THEN '<=5' ELSE '>5' END AS los_group,
    a.hospital_expire_flag,
    COALESCE(df.has_ckd, 0) AS has_ckd,
    COALESCE(df.has_diabetes, 0) AS has_diabetes,
    COALESCE(df.has_afib, 0) AS has_afib,
    COALESCE(df.has_htn, 0) AS has_htn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  LEFT JOIN
    diag_flags df
  USING (hadm_id)
  WHERE
    -- Demographics: men age 75-85
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    -- Must have sepsis (excluding septic shock)
    AND COALESCE(df.has_sepsis_noshock, 0) = 1
    AND COALESCE(df.has_septic_shock, 0) = 0
    -- Require admission/discharge timestamps to compute LOS and determine in-hospital death
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)

-- Unpivot comorbidities so we can stratify by comorbidity presence/absence and LOS group
SELECT
  comorbidity,
  CASE WHEN present = 1 THEN 'present' ELSE 'absent' END AS presence,
  los_group,
  COUNT(*) AS admissions_n,
  SUM(hospital_expire_flag) AS deaths_n,
  ROUND(100.0 * SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)), 2) AS mortality_pct
FROM (
  SELECT
    c.*,
    v.comorbidity,
    v.present
  FROM
    cohort c,
    UNNEST([
      STRUCT('CKD' AS comorbidity, c.has_ckd AS present),
      STRUCT('Diabetes' AS comorbidity, c.has_diabetes AS present),
      STRUCT('AFib' AS comorbidity, c.has_afib AS present),
      STRUCT('Hypertension' AS comorbidity, c.has_htn AS present)
    ]) AS v
)
GROUP BY
  comorbidity,
  presence,
  los_group
ORDER BY
  comorbidity,
  presence DESC,
  los_group;