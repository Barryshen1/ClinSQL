WITH first_admissions AS (
  -- first hospital admission per patient
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS adm_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
),
anticoag_hadm AS (
  -- hadm_ids (from first admission cohort) with at least one anticoagulant prescription overlapping the admission
  SELECT DISTINCT
    fa.subject_id,
    fa.hadm_id
  FROM
    first_admissions fa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = fa.hadm_id
  WHERE
    fa.adm_rank = 1
    -- prescription overlaps admission window
    AND pr.starttime < fa.dischtime
    AND (pr.stoptime IS NULL OR pr.stoptime > fa.admittime)
    -- crude text match for common anticoagulants in prescriptions.drug
    AND (
      LOWER(COALESCE(pr.drug, '')) LIKE '%warfarin%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%coumadin%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%heparin%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%enoxaparin%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%lovenox%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%apixaban%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%eliquis%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%rivaroxaban%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%xarelto%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%dabigatran%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%pradaxa%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%fondaparinux%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%edoxaban%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%savaysa%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%bivalirudin%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%argatroban%'
    )
),
first_icustays AS (
  -- first ICU stay per subject within each hadm (we'll later restrict to first admission hadm)
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id, i.hadm_id ORDER BY i.intime) AS icu_rank
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
)
SELECT
  -- approximate median (50th percentile) LOS in days among females age 50-60 on anticoagulants
  APPROX_QUANTILES(fis.los, 100)[OFFSET(50)] AS median_icu_los_days,
  COUNT(1) AS n_patients
FROM
  first_admissions fa
JOIN
  anticoag_hadm ah
  ON fa.subject_id = ah.subject_id AND fa.hadm_id = ah.hadm_id
JOIN
  first_icustays fis
  ON fis.subject_id = fa.subject_id AND fis.hadm_id = fa.hadm_id
WHERE
  fa.adm_rank = 1
  AND fis.icu_rank = 1
  -- ensure LOS is non-null and non-negative
  AND fis.los IS NOT NULL
  AND fis.los >= 0;