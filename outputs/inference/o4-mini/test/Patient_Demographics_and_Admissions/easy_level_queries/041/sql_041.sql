WITH female_50_60 AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
),
first_admission AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    female_50_60 f
  ON
    a.subject_id = f.subject_id
),
first_adm_with_anticoag AS (
  SELECT DISTINCT
    fa.subject_id,
    fa.hadm_id
  FROM
    first_admission fa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON
    fa.subject_id = pr.subject_id
    AND fa.hadm_id = pr.hadm_id
  WHERE
    fa.rn = 1
    AND (
      LOWER(pr.drug) LIKE '%warfarin%'
      OR LOWER(pr.drug) LIKE '%heparin%'
      OR LOWER(pr.drug) LIKE '%enoxaparin%'
      OR LOWER(pr.drug) LIKE '%apixaban%'
      OR LOWER(pr.drug) LIKE '%dabigatran%'
      OR LOWER(pr.drug) LIKE '%rivaroxaban%'
      OR LOWER(pr.drug) LIKE '%fondaparinux%'
    )
),
first_icu_stay AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.los,
    ROW_NUMBER() OVER (PARTITION BY ic.subject_id ORDER BY ic.intime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN
    first_adm_with_anticoag fa
  ON
    ic.subject_id = fa.subject_id
    AND ic.hadm_id = fa.hadm_id
)
SELECT
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_icu_los_days
FROM
  first_icu_stay
WHERE
  rn = 1;