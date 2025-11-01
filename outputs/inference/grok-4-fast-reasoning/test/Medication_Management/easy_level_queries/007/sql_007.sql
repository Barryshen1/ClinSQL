WITH cohort AS (
  SELECT
    TIMESTAMP_DIFF(pres.stoptime, pres.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON
    pat.subject_id = adm.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
  ON
    adm.subject_id = pres.subject_id AND adm.hadm_id = pres.hadm_id
  WHERE
    pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 90 AND 100
    AND pres.hadm_id IS NOT NULL
    AND pres.stoptime IS NOT NULL
    AND pres.starttime IS NOT NULL
    AND pres.stoptime > pres.starttime
    AND TIMESTAMP_DIFF(pres.stoptime, pres.starttime, DAY) > 0
    AND (
      LOWER(COALESCE(pres.drug, '')) LIKE '%hydrochlorothiazide%'
      OR LOWER(COALESCE(pres.drug, '')) LIKE '%chlorthalidone%'
      OR LOWER(COALESCE(pres.drug, '')) LIKE '%indapamide%'
      OR LOWER(COALESCE(pres.drug, '')) LIKE '%metolazone%'
    )
)
SELECT
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY duration_days) -
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY duration_days) AS iqr_duration_days
FROM
  cohort;