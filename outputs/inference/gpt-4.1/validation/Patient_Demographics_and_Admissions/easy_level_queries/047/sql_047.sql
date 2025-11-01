WITH aki_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 82 AND 92
    AND (
      (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%')
      OR
      (diag.icd_version = 9 AND diag.icd_code LIKE '584%')
    )
)

, first_icu_stays AS (
  SELECT
    aki.subject_id,
    aki.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los
  FROM
    aki_admissions aki
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON aki.subject_id = icu.subject_id
      AND aki.hadm_id = icu.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY aki.hadm_id ORDER BY icu.intime) = 1
)

SELECT
  PERCENTILE_CONT(los, 0.25) OVER () AS los_25th_percentile
FROM
  first_icu_stays;