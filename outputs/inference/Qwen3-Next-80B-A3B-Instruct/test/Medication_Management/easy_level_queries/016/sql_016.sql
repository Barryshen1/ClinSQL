SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(0)] AS twenty_fifth_percentile_duration_days
FROM (
  SELECT
    DATE_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    physionet-data.mimiciv_3_1_hosp.prescriptions p
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
    ON p.subject_id = pat.subject_id
  WHERE
    pat.anchor_age BETWEEN 76 AND 86
    AND pat.gender = 'M'
    AND p.stoptime IS NOT NULL
    AND p.starttime IS NOT NULL
    AND p.stoptime > p.starttime
    AND (
      LOWER(p.drug) LIKE '%nitroglycerin%'
      OR LOWER(p.drug) LIKE '%isosorbide dinitrate%'
      OR LOWER(p.drug) LIKE '%isosorbide mononitrate%'
      OR LOWER(p.drug) LIKE '%nitroprusside%'
    )
    AND p.route IN ('IV', 'PO', 'SL')
) p;