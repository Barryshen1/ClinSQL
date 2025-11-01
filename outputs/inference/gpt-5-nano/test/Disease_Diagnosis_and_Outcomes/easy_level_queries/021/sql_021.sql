WITH female_58_68 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 58 AND 68
),
admissions_with_los AS (
  SELECT a.hadm_id,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN female_58_68 f ON f.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dic
    ON dic.subject_id = a.subject_id AND dic.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dd.icd_code = dic.icd_code AND dd.icd_version = dic.icd_version
  WHERE a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
  GROUP BY a.hadm_id, a.admittime, a.dischtime
  HAVING MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title), 'hemorrhag|stroke') THEN 1 ELSE 0 END) = 1
     AND MAX(CASE WHEN REGEXP_CONTAINS(LOWER(dd.long_title), 'copd|exacerbat') THEN 1 ELSE 0 END) = 1
)
SELECT
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS los_iqr_days
FROM (
  SELECT APPROX_QUANTILES(los_days, 4) AS quantiles
  FROM admissions_with_los
  WHERE los_days IS NOT NULL
) t;