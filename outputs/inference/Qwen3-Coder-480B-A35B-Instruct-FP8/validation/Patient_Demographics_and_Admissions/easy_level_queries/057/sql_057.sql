WITH first_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime AS first_admittime
  FROM (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM
      physionet-data.mimiciv_3_1_hosp.admissions
  )
  WHERE rn = 1
),
stroke_patients AS (
  SELECT DISTINCT
    d.subject_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%stroke%'
    OR LOWER(dd.long_title) LIKE '%cerebrovascular accident%'
),
first_icu_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.los AS icu_los,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    first_admissions fa
    ON icu.hadm_id = fa.hadm_id
)
SELECT
  APPROX_QUANTILES(icu_los, 4)[OFFSET(3)] - APPROX_QUANTILES(icu_los, 4)[OFFSET(1)] AS iqr_icu_los_days
FROM
  first_icu_stays fis
JOIN
  physionet-data.mimiciv_3_1_hosp.patients p
  ON fis.subject_id = p.subject_id
JOIN
  stroke_patients sp
  ON fis.subject_id = sp.subject_id
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 46 AND 56
  AND fis.rn = 1;