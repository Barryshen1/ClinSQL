WITH female_age77_87 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 77 AND 87
),
dialysis_admissions AS (
  SELECT DISTINCT p.subject_id, pr.hadm_id
  FROM female_age77_87 p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  WHERE (
    -- ICD-9 dialysis codes
    (pr.icd_version = 9 AND pr.icd_code IN ('3995', '5498'))
    -- ICD-10 dialysis codes
    OR (pr.icd_version = 10 AND pr.icd_code IN ('5A1D00Z', '5A1D60Z'))
  )
),
first_icu_stays AS (
  SELECT
    da.subject_id,
    da.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los
  FROM dialysis_admissions da
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON da.subject_id = icu.subject_id
    AND da.hadm_id = icu.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY da.subject_id ORDER BY icu.intime) = 1
)
SELECT
  quantiles[OFFSET(1)] AS Q1,
  quantiles[OFFSET(3)] AS Q3,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS IQR
FROM (
  SELECT
    APPROX_QUANTILES(los, 4) AS quantiles
  FROM first_icu_stays
  WHERE los IS NOT NULL AND los > 0
);