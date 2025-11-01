WITH ace_prescriptions AS (
  SELECT
    DATETIME_DIFF(rx.stoptime, rx.starttime, SECOND) / 86400.0 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON adm.hadm_id = rx.hadm_id AND adm.subject_id = rx.subject_id
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM adm.admittime) - (p.anchor_year - p.anchor_age)) = 55
    AND rx.stoptime IS NOT NULL
    AND rx.stoptime >= rx.starttime
    AND REGEXP_CONTAINS(LOWER(rx.drug), r'captopril|enalapril|lisinopril|ramipril|quinapril|perindopril|trandolapril|benazepril|fosinopril|moexipril')
)
SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS percentile_25_duration_days
FROM
  ace_prescriptions;