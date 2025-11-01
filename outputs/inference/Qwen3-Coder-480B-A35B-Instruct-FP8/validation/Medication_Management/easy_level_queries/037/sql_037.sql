SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS percentile_25_duration_days
FROM (
  SELECT
    DATETIME_DIFF(stoptime, starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON
    pr.subject_id = pt.subject_id
  WHERE
    pt.gender = 'F'
    AND pt.anchor_age = 55
    AND pr.drug IS NOT NULL
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(pr.drug), r'(lisinopril|enalapril|ramipril|captopril|perindopril|quinapril|fosinopril|benazepril|moexipril|trandolapril)')
    AND DATETIME_DIFF(stoptime, starttime, DAY) > 0
) AS valid_durations;