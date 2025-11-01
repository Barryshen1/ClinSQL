WITH cohort AS (
  -- Select male patients aged 64-74 at admission
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 64 AND 74
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
),
sepsis_flags AS (
  -- For each admission, flag sepsis (not septic shock), CKD, diabetes
  SELECT
    c.subject_id,
    c.hadm_id,
    c.los,
    c.hospital_expire_flag,
    -- Sepsis flag: at least one sepsis code, no septic shock code
    MAX(
      CASE
        WHEN
          (
            -- ICD-10 sepsis
            (d.icd_version = 10 AND (
              REGEXP_CONTAINS(d.icd_code, r'^A41') OR
              d.icd_code IN ('R6520') -- R65.20
            ))
            OR
            -- ICD-9 sepsis
            (d.icd_version = 9 AND d.icd_code IN ('99591'))
          )
        THEN 1 ELSE 0
      END
    ) AS has_sepsis,
    MAX(
      CASE
        WHEN
          (
            -- ICD-10 septic shock
            (d.icd_version = 10 AND (
              d.icd_code IN ('R6521', 'T8112')
            ))
            OR
            -- ICD-9 septic shock
            (d.icd_version = 9 AND d.icd_code IN ('78552'))
          )
        THEN 1 ELSE 0
      END
    ) AS has_septic_shock,
    MAX(
      CASE
        WHEN
          (
            -- ICD-10 CKD
            (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^N18'))
            OR
            -- ICD-9 CKD
            (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^585'))
          )
        THEN 1 ELSE 0
      END
    ) AS has_ckd,
    MAX(
      CASE
        WHEN
          (
            -- ICD-10 diabetes
            (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E1[0-4]'))
            OR
            -- ICD-9 diabetes
            (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^250'))
          )
        THEN 1 ELSE 0
      END
    ) AS has_diabetes
  FROM
    cohort c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  GROUP BY
    c.subject_id, c.hadm_id, c.los, c.hospital_expire_flag
),
final_cohort AS (
  -- Only admissions with sepsis (not septic shock)
  SELECT
    subject_id,
    hadm_id,
    los,
    hospital_expire_flag,
    has_ckd,
    has_diabetes
  FROM
    sepsis_flags
  WHERE
    has_sepsis = 1
    AND has_septic_shock = 0
    AND los IS NOT NULL
),
quartiles AS (
  -- Assign LOS quartiles
  SELECT
    *,
    NTILE(4) OVER (ORDER BY los) AS los_quartile
  FROM
    final_cohort
)
SELECT
  los_quartile AS LOS_quartile,
  COUNT(*) AS admissions,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 3) AS in_hospital_mortality_rate,
  ROUND(SUM(has_ckd) / COUNT(*), 3) AS ckd_prevalence,
  ROUND(SUM(has_diabetes) / COUNT(*), 3) AS diabetes_prevalence
FROM
  quartiles
GROUP BY
  los_quartile
ORDER BY
  los_quartile;