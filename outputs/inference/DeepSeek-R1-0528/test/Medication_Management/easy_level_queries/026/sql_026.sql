WITH cohort AS (
  SELECT
    DATE_DIFF(Rxs.stoptime, Rxs.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` Pt
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` Ad
    ON Pt.subject_id = Ad.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` Rxs
    ON Ad.hadm_id = Rxs.hadm_id
    AND Pt.subject_id = Rxs.subject_id
  WHERE
    Pt.gender = 'F'
    AND Rxs.stoptime IS NOT NULL
    AND (Pt.anchor_age + (EXTRACT(YEAR FROM Ad.admittime) - Pt.anchor_year)) BETWEEN 81 AND 91
    AND (
      LOWER(Rxs.drug) LIKE '%amlodipine%'
      OR LOWER(Rxs.drug) LIKE '%nifedipine%'
      OR LOWER(Rxs.drug) LIKE '%felodipine%'
      OR LOWER(Rxs.drug) LIKE '%nicardipine%'
      OR LOWER(Rxs.drug) LIKE '%nimodipine%'
      OR LOWER(Rxs.drug) LIKE '%isradipine%'
      OR LOWER(Rxs.drug) LIKE '%nisoldipine%'
    )
)
SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS percentile_25_duration_days
FROM cohort;