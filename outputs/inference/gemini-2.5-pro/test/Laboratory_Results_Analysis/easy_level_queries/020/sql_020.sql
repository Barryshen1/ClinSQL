WITH NadirHemoglobinPerStay AS (
  -- This CTE identifies all relevant hospital stays and computes the nadir hemoglobin for each.
  SELECT
    le.hadm_id,
    MIN(le.valuenum) AS nadir_hgb
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  -- We perform an INNER JOIN with diagnoses to exclusively select heart failure admissions.
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON le.hadm_id = dx.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  -- We also INNER JOIN with patients to filter for males.
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON le.subject_id = p.subject_id
  WHERE
    -- Filter for Hemoglobin lab item
    le.itemid = 51222
    -- Ensure the value is a valid number
    AND le.valuenum IS NOT NULL
    -- Filter for male patients
    AND p.gender = 'M'
    -- Filter for heart failure diagnoses
    AND LOWER(d_dx.long_title) LIKE '%heart failure%'
  GROUP BY
    le.hadm_id
)
-- From the set of nadir hemoglobin values, calculate the 75th percentile.
SELECT
  APPROX_QUANTILES(nadir_hgb, 100)[OFFSET(75)] AS p75_nadir_hemoglobin
FROM
  NadirHemoglobinPerStay;