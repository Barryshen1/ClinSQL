WITH HF_patients AS (
  SELECT DISTINCT di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON di.subject_id = p.subject_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 79 AND 89
    AND LOWER(dd.long_title) LIKE '%heart failure%'
),
first_admission AS (
  SELECT a.subject_id,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN HF_patients AS f ON a.subject_id = f.subject_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime ASC) = 1
)
SELECT
  quantiles[OFFSET(1)] AS p25_days,
  quantiles[OFFSET(3)] AS p75_days,
  (quantiles[OFFSET(3)] - quantiles[OFFSET(1)]) AS iqr_days
FROM (
  SELECT APPROX_QUANTILES(los_days, 4) AS quantiles
  FROM first_admission
);