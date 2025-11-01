WITH cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 45 AND 55
    AND icu.los >= 2
    AND (
      (d_dx.icd_code LIKE 'E11%' AND d_dx.icd_version = 10)
      OR (d_dx.icd_code LIKE '250.0%' AND d_dx.icd_version = 9)
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_dx2
        ON dx2.icd_code = d_dx2.icd_code AND dx2.icd_version = d_dx2.icd_version
      WHERE dx2.hadm_id = icu.hadm_id
        AND (
          (d_dx2.icd_code LIKE 'I50%' AND d_dx2.icd_version = 10)
          OR (d_dx2.icd_code LIKE '428%' AND d_dx2.icd_version = 9)
        )
    )
),

meds_first_48h AS (
  SELECT DISTINCT
    emar.subject_id,
    CASE
      WHEN LOWER(emar.medication) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(emar.medication) LIKE '%metformin%'
        OR LOWER(emar.medication) LIKE '%glyburide%'
        OR LOWER(emar.medication) LIKE '%glipizide%' THEN 'Oral'
    END AS med_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` emar
  JOIN cohort c
    ON emar.subject_id = c.subject_id
    AND emar.charttime BETWEEN c.intime AND c.intime + INTERVAL 48 HOUR
  WHERE
    CASE
      WHEN LOWER(emar.medication) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(emar.medication) LIKE '%metformin%'
        OR LOWER(emar.medication) LIKE '%glyburide%'
        OR LOWER(emar.medication) LIKE '%glipizide%' THEN 'Oral'
    END IS NOT NULL
),

meds_last_24h AS (
  SELECT DISTINCT
    emar.subject_id,
    CASE
      WHEN LOWER(emar.medication) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(emar.medication) LIKE '%metformin%'
        OR LOWER(emar.medication) LIKE '%glyburide%'
        OR LOWER(emar.medication) LIKE '%glipizide%' THEN 'Oral'
    END AS med_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` emar
  JOIN cohort c
    ON emar.subject_id = c.subject_id
    AND emar.charttime BETWEEN c.outtime - INTERVAL 24 HOUR AND c.outtime
  WHERE
    CASE
      WHEN LOWER(emar.medication) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(emar.medication) LIKE '%metformin%'
        OR LOWER(emar.medication) LIKE '%glyburide%'
        OR LOWER(emar.medication) LIKE '%glipizide%' THEN 'Oral'
    END IS NOT NULL
),

cohort_count AS (
  SELECT COUNT(DISTINCT subject_id) AS total_patients FROM cohort
),

first_48h_stats AS (
  SELECT
    med_type,
    COUNT(DISTINCT subject_id) AS cnt
  FROM meds_first_48h
  GROUP BY med_type
),

last_24h_stats AS (
  SELECT
    med_type,
    COUNT(DISTINCT subject_id) AS cnt
  FROM meds_last_24h
  GROUP BY med_type
)

SELECT
  'First 48 Hours' AS time_window,
  'Insulin' AS med_category,
  ROUND(
    (SELECT cnt FROM first_48h_stats WHERE med_type = 'Insulin') * 100.0 /
    (SELECT total_patients FROM cohort_count),
    2
  ) AS percentage
UNION ALL
SELECT
  'First 48 Hours',
  'Oral',
  ROUND(
    (SELECT cnt FROM first_48h_stats WHERE med_type = 'Oral') * 100.0 /
    (SELECT total_patients FROM cohort_count),
    2
  )
UNION ALL
SELECT
  'Final 24 Hours',
  'Insulin',
  ROUND(
    (SELECT cnt FROM last_24h_stats WHERE med_type = 'Insulin') * 100.0 /
    (SELECT total_patients FROM cohort_count),
    2
  )
UNION ALL
SELECT
  'Final 24 Hours',
  'Oral',
  ROUND(
    (SELECT cnt FROM last_24h_stats WHERE med_type = 'Oral') * 100.0 /
    (SELECT total_patients FROM cohort_count),
    2
  );