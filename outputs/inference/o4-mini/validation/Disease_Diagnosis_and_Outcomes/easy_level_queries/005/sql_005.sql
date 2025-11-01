WITH stroke_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    -- primary diagnosis stroke
    JOIN (
      SELECT
        d.subject_id,
        d.hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
          ON d.icd_code = dd.icd_code
          AND d.icd_version = dd.icd_version
      WHERE
        d.seq_num = 1
        AND (
          LOWER(dd.long_title) LIKE '%ischemic stroke%'
          OR LOWER(dd.long_title) LIKE '%cerebral infarction%'
        )
    ) AS stroke
      ON a.subject_id = stroke.subject_id
      AND a.hadm_id    = stroke.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
)

SELECT
  -- approximate median (50th percentile)
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days
FROM
  stroke_cohort;