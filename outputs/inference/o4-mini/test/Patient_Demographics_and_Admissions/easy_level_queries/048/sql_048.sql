WITH hf_subjects AS (
  -- Subjects with any heart failure diagnosis
  SELECT DISTINCT di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
),
first_admission_los AS (
  -- Compute LOS for each subject's first admission
  SELECT
    a.subject_id,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los
  FROM (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 79 AND 89
      AND a.subject_id IN (SELECT subject_id FROM hf_subjects)
  ) a
  WHERE a.rn = 1
)
SELECT
  quantiles[OFFSET(1)] AS iqr_25th_day,
  quantiles[OFFSET(3)] AS iqr_75th_day
FROM (
  SELECT
    APPROX_QUANTILES(los, 4) AS quantiles
  FROM first_admission_los
);