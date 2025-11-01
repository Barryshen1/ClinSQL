WITH patient_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los,
    CASE 
      WHEN icu.stay_id IS NOT NULL THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_status
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND EXISTS (
      -- Has at least one surgical procedure
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
      WHERE proc.hadm_id = a.hadm_id
    )
    AND EXISTS (
      -- Has at least one postoperative complication diagnosis
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddiag
        ON diag.icd_code = ddiag.icd_code
        AND diag.icd_version = ddiag.icd_version
      WHERE diag.hadm_id = a.hadm_id
        AND (
          LOWER(ddiag.long_title) LIKE '%postoperative%'
          OR LOWER(ddiag.long_title) LIKE '%post-op%'
          OR LOWER(ddiag.long_title) LIKE '%complication%'
          OR LOWER(ddiag.long_title) LIKE '%sepsis%'
          OR LOWER(ddiag.long_title) LIKE '%infection%'
          OR LOWER(ddiag.long_title) LIKE '%hemorrhage%'
          OR LOWER(ddiag.long_title) LIKE '%respiratory failure%'
        )
    )
),
comorbidity_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),
final_cohort AS (
  SELECT
    pc.hadm_id,
    pc.icu_status,
    pc.los,
    pc.hospital_expire_flag,
    cc.comorbidity_count,
    CASE
      WHEN pc.los <= 5 THEN '≤5'
      ELSE '>5'
    END AS los_bin,
    CASE
      WHEN cc.comorbidity_count <= 1 THEN '0-1'
      WHEN cc.comorbidity_count = 2 THEN '2'
      ELSE '>=3'
    END AS comorbidity_bin
  FROM
    patient_cohort pc
  INNER JOIN
    comorbidity_counts cc
    ON pc.hadm_id = cc.hadm_id
)
SELECT
  icu_status,
  los_bin,
  comorbidity_bin,
  COUNT(*) AS N,
  AVG(hospital_expire_flag * 100.0) AS in_hospital_mortality_percent,
  AVG(comorbidity_count) AS average_comorbidity_count
FROM
  final_cohort
GROUP BY
  icu_status,
  los_bin,
  comorbidity_bin
ORDER BY
  icu_status,
  los_bin,
  comorbidity_bin;