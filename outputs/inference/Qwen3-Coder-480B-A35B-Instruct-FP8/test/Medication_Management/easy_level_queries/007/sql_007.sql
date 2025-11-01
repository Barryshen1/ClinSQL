SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS iqr_days
FROM (
  SELECT
    DATETIME_DIFF(stoptime, starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
  USING
    (subject_id)
  WHERE
    pt.gender = 'F'
    AND pt.anchor_age BETWEEN 90 AND 100
    AND pr.drug IS NOT NULL
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime >= pr.starttime
    AND REGEXP_CONTAINS(LOWER(pr.drug), r'(thiazide|hydrochlorothiazide|chlorthalidone|indapamide|metolazone|chlorothiazide)')
) AS valid_durations
WHERE
  duration_days >= 0;