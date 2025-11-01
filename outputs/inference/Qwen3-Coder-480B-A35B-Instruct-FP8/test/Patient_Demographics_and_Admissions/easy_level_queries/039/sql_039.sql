WITH pneumonia_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%pneumonia%'
),
first_icu_stays AS (
  SELECT
    icu.subject_id,
    icu.stay_id,
    icu.los,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    pneumonia_admissions pa
    ON icu.hadm_id = pa.hadm_id
)
SELECT
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS icu_los_25th_percentile
FROM
  first_icu_stays
JOIN
  physionet-data.mimiciv_3_1_hosp.patients p
  ON first_icu_stays.subject_id = p.subject_id
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 43 AND 53
  AND first_icu_stays.rn = 1;