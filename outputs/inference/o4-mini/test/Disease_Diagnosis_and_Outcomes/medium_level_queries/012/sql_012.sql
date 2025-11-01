WITH heart_failure_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    CASE
      WHEN icu.stay_id IS NOT NULL THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON a.subject_id = icu.subject_id
     AND a.hadm_id = icu.hadm_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 83 AND 93
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = a.hadm_id
          AND (
            -- ICD-9 heart failure codes start with 428
            (d.icd_version = 9 AND STARTS_WITH(d.icd_code, '428'))
            OR
            -- ICD-10 heart failure codes start with I50
            (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'I50'))
          )
      )
),
comorbidity_flags AS (
  SELECT
    hfa.subject_id,
    hfa.hadm_id,
    hfa.icu_flag,
    hfa.los,
    hfa.hospital_expire_flag,
    -- LOS category
    CASE
      WHEN hfa.los < 8 THEN '<8'
      ELSE '>=8'
    END AS los_cat,
    -- Count non-HF diagnoses
    COUNT(DISTINCT CASE
      WHEN NOT (
        (d.icd_version = 9 AND STARTS_WITH(d.icd_code, '428'))
        OR (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'I50'))
      ) THEN d.icd_code
    END) AS comorbidity_count,
    -- CKD flag
    MAX(
      CASE
        WHEN (d.icd_version = 9 AND STARTS_WITH(d.icd_code, '585'))
          OR (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'N18'))
        THEN 1 ELSE 0
      END
    ) AS ckd_flag,
    -- Diabetes flag
    MAX(
      CASE
        WHEN (d.icd_version = 9 AND STARTS_WITH(d.icd_code, '250'))
          OR (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'E11'))
        THEN 1 ELSE 0
      END
    ) AS diab_flag
  FROM
    heart_failure_adm hfa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON hfa.subject_id = d.subject_id
     AND hfa.hadm_id = d.hadm_id
  GROUP BY
    hfa.subject_id,
    hfa.hadm_id,
    hfa.icu_flag,
    hfa.los,
    hfa.hospital_expire_flag
),
comorbidity_cat AS (
  SELECT
    subject_id,
    hadm_id,
    icu_flag,
    los,
    hospital_expire_flag,
    los_cat,
    ckd_flag,
    diab_flag,
    CASE
      WHEN comorbidity_count <= 1 THEN '0-1'
      WHEN comorbidity_count = 2 THEN '2'
      ELSE '>=3'
    END AS comorbidity_category
  FROM comorbidity_flags
)
SELECT
  icu_flag,
  los_cat,
  comorbidity_category,
  COUNT(1) AS n_admissions,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(1), 1) AS mortality_pct,
  -- median LOS
  CAST(
    APPROX_QUANTILES(los, 2)[OFFSET(1)]
    AS INT64
  ) AS median_los_days,
  ROUND(100.0 * SUM(ckd_flag) / COUNT(1), 1) AS ckd_prevalence_pct,
  ROUND(100.0 * SUM(diab_flag) / COUNT(1), 1) AS diabetes_prevalence_pct
FROM
  comorbidity_cat
GROUP BY
  icu_flag,
  los_cat,
  comorbidity_category
ORDER BY
  icu_flag,
  los_cat,
  comorbidity_category;