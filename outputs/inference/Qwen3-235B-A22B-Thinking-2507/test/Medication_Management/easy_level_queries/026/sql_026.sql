WITH filtered_prescriptions AS (
  SELECT
    TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) / 86400.0 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.hadm_id = a.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND p.stoptime IS NOT NULL
    AND p.stoptime >= p.starttime
    AND REGEXP_CONTAINS(LOWER(p.drug), r'amlodipine|nifedipine|felodipine|nicardipine|isradipine|nisoldipine')
    AND (pat.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pat.anchor_year)) BETWEEN 81 AND 91
)
SELECT
  APPROX_QUANTILES(duration_days, 1000)[OFFSET(250)] AS percentile_25
FROM
  filtered_prescriptions;