WITH aki_hadm AS (
  SELECT DISTINCT hadm_id, subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '584%')
     OR (icd_version = 10 AND icd_code LIKE 'N17%')
),
cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 82 AND 92
),
aki_icustays AS (
  -- ICU stays that belong to admissions with AKI and to cohort patients
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN aki_hadm a
    ON i.hadm_id = a.hadm_id AND i.subject_id = a.subject_id
  JOIN cohort c
    ON i.subject_id = c.subject_id
)
SELECT
  -- approximate 25th percentile (first quartile) of first ICU LOS (days)
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS p25_first_icu_los_days,
  COUNT(*) AS n_subjects_included
FROM aki_icustays
WHERE rn = 1
  AND los IS NOT NULL;