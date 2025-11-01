WITH heart_failure_adms AS (
  -- Select female 80–90 y/o admissions with heart failure diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON a.subject_id = di.subject_id
     AND a.hadm_id    = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code    = dd.icd_code
     AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND LOWER(dd.long_title) LIKE '%heart failure%'
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
),
admission_flags AS (
  -- Annotate ICU flag, LOS group, CKD flag, diabetes flag
  SELECT
    hfa.subject_id,
    hfa.hadm_id,
    hfa.hospital_expire_flag,
    -- ICU if any icustay record exists
    IF(ics.stay_id IS NOT NULL, 'ICU', 'Non-ICU') AS icu_group,
    -- LOS in days, classify <8 vs >=8
    CASE
      WHEN DATE_DIFF(hfa.dischtime, hfa.admittime, DAY) < 8 THEN '<8 days'
      ELSE '>=8 days'
    END AS los_group,
    -- CKD flag: any diag code N18% (ICD10) or 585% (ICD9)
    MAX(
      CASE
        WHEN (di.icd_version = 10 AND di.icd_code LIKE 'N18%')
          OR (di.icd_version = 9 AND di.icd_code LIKE '585%')
        THEN 1 ELSE 0
      END
    ) OVER (PARTITION BY hfa.subject_id, hfa.hadm_id) AS ckd_flag,
    -- Diabetes flag: any diag code E10–E14 (ICD10) or 250% (ICD9)
    MAX(
      CASE
        WHEN (di.icd_version = 10 AND di.icd_code BETWEEN 'E10' AND 'E14')
          OR (di.icd_version = 9 AND di.icd_code LIKE '250%')
        THEN 1 ELSE 0
      END
    ) OVER (PARTITION BY hfa.subject_id, hfa.hadm_id) AS diabetes_flag
  FROM
    heart_failure_adms hfa
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` ics
      ON hfa.subject_id = ics.subject_id
     AND hfa.hadm_id    = ics.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON hfa.subject_id = di.subject_id
     AND hfa.hadm_id    = di.hadm_id
),
agg AS (
  -- Aggregate outcomes and prevalences
  SELECT
    icu_group,
    los_group,
    COUNT(*) AS total_admissions,
    100.0 * SUM(hospital_expire_flag) / COUNT(*) AS mortality_pct,
    100.0 * SUM(ckd_flag) / COUNT(*) AS ckd_prevalence_pct,
    100.0 * SUM(diabetes_flag) / COUNT(*) AS diabetes_prevalence_pct
  FROM
    admission_flags
  GROUP BY
    icu_group,
    los_group
)
SELECT
  icu_group,
  los_group,
  total_admissions,
  ROUND(mortality_pct, 1)      AS in_hospital_mortality_pct,
  ROUND(ckd_prevalence_pct, 1) AS ckd_prevalence_pct,
  ROUND(diabetes_prevalence_pct, 1) AS diabetes_prevalence_pct
FROM
  agg
ORDER BY
  icu_group,
  los_group;