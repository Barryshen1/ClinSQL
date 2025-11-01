WITH patients_filtered AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    DATETIME_ADD(a.admittime, INTERVAL p.anchor_year - EXTRACT(YEAR FROM a.admittime) YEAR) AS anchor_time_adjusted,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 53 AND 63
),
icu_stays_filtered AS (
  SELECT
    i.hadm_id,
    i.los,
    CASE
      WHEN i.los BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN i.los BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE NULL
    END AS stay_group
  FROM
    `physionet-data.mimiciv_3_1_icu`.icustays i
  WHERE
    i.los >= 1 AND i.los <= 8
),
upper_gi_bleed_admissions AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%upper gastrointestinal bleed%'
    OR LOWER(dd.long_title) LIKE '%upper gi bleed%'
    OR LOWER(dd.long_title) LIKE '%hematemesis%'
    OR LOWER(dd.long_title) LIKE '%melena%'
),
diagnostic_procedures AS (
  SELECT
    p.hadm_id,
    COUNT(*) AS procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp`.procedures_icd p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures dp
  ON
    p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%endoscopy%'
    OR LOWER(dp.long_title) LIKE '%gastroscopy%'
    OR LOWER(dp.long_title) LIKE '%esophagogastroduodenoscopy%'
    OR LOWER(dp.long_title) LIKE '%diagnostic%'
    OR LOWER(dp.long_title) LIKE '%upper gi%'
  GROUP BY
    p.hadm_id
),
admissions_with_procedures AS (
  SELECT
    pf.hadm_id,
    ifs.stay_group,
    COALESCE(dp.procedure_count, 0) AS procedure_count
  FROM
    patients_filtered pf
  INNER JOIN
    icu_stays_filtered ifs
  ON
    pf.hadm_id = ifs.hadm_id
  INNER JOIN
    upper_gi_bleed_admissions ugb
  ON
    pf.hadm_id = ugb.hadm_id
  LEFT JOIN
    diagnostic_procedures dp
  ON
    pf.hadm_id = dp.hadm_id
  WHERE
    ifs.stay_group IS NOT NULL
)
SELECT
  stay_group,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(25)] AS p25_procedures,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(50)] AS p50_procedures,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] AS p75_procedures
FROM
  admissions_with_procedures
GROUP BY
  stay_group
ORDER BY
  stay_group;