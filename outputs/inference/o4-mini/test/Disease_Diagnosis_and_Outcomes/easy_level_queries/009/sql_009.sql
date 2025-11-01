WITH male_elderly_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
),
hadm_diagnosis_flags AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(CASE
          WHEN icd_version = 9
           AND (
             icd_code LIKE '410%' OR icd_code LIKE '411%'
             OR icd_code LIKE '412%' OR icd_code LIKE '413%'
             OR icd_code LIKE '414%'
           )
          THEN 1 ELSE 0
        END) AS has_ihd,
    MAX(CASE
          WHEN icd_version = 9
           AND (
             icd_code LIKE '490%' OR icd_code LIKE '491%'
             OR icd_code LIKE '492%' OR icd_code LIKE '493%'
             OR icd_code LIKE '494%' OR icd_code LIKE '495%'
             OR icd_code LIKE '496%'
           )
          THEN 1 ELSE 0
        END) AS has_copd
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    subject_id,
    hadm_id
)
SELECT
  -- 75th percentile of hospital LOS (in days)
  APPROX_QUANTILES(m.laos, 100)[SAFE_OFFSET(75)] AS los_days_p75
FROM (
  SELECT
    mea.los_days AS laos
  FROM
    male_elderly_admissions mea
    JOIN hadm_diagnosis_flags hdf
      ON mea.subject_id = hdf.subject_id
     AND mea.hadm_id = hdf.hadm_id
  WHERE
    hdf.has_ihd = 1
    AND hdf.has_copd = 1
) m;