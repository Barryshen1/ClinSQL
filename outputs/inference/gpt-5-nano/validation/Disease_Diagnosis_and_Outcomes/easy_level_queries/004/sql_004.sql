WITH dka_primary AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE di.seq_num = 1
    AND (
      LOWER(dd.long_title) LIKE '%diabetic ketoacidosis%'
      OR LOWER(dd.long_title) LIKE '%ketoacidosis%'
      OR LOWER(dd.long_title) LIKE '%hyperosmolar%'
      OR LOWER(dd.long_title) LIKE '%hyperosmolar state%'
    )
)
SELECT quantiles[OFFSET(25)] AS p25_los_days
FROM (
  SELECT APPROX_QUANTILES(los_days, 100) AS quantiles
  FROM (
    SELECT
      TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN dka_primary AS d
      ON d.hadm_id = a.hadm_id AND d.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON p.subject_id = a.subject_id
    WHERE
      (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 73 AND 83
      AND LOWER(p.gender) IN ('m', 'male')
      AND a.dischtime IS NOT NULL
      AND a.admittime IS NOT NULL
  )
) t;