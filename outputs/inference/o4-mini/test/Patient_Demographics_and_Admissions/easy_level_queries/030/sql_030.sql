WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    ROW_NUMBER() OVER (
      PARTITION BY a.subject_id
      ORDER BY a.admittime
    ) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
),
eligible AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    TIMESTAMP_DIFF(fa.dischtime, fa.admittime, SECOND) / 86400.0 AS los_days
  FROM
    first_admissions fa
  WHERE
    fa.rn = 1
    AND EXISTS (
      SELECT
        1
      FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
      WHERE
        rx.subject_id = fa.subject_id
        AND rx.hadm_id = fa.hadm_id
        AND rx.starttime BETWEEN fa.admittime AND fa.dischtime
        AND (
          LOWER(rx.drug) LIKE '%heparin%'
          OR LOWER(rx.drug) LIKE '%warfarin%'
          OR LOWER(rx.drug) LIKE '%apixaban%'
          OR LOWER(rx.drug) LIKE '%rivaroxaban%'
          OR LOWER(rx.drug) LIKE '%dabigatran%'
          OR LOWER(rx.drug) LIKE '%edoxaban%'
        )
    )
)
SELECT
  STDDEV_SAMP(los_days) AS sd_los_days
FROM
  eligible;