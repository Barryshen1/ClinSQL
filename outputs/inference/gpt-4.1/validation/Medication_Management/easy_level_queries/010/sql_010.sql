SELECT
  STDDEV(duration_days) AS nitrate_prescription_duration_sd
FROM (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    -- Duration in days, inclusive
    DATE_DIFF(CAST(pr.stoptime AS DATE), CAST(pr.starttime AS DATE), DAY) + 1 AS duration_days
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
    INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
      ON p.subject_id = a.subject_id
    INNER JOIN physionet-data.mimiciv_3_1_hosp.prescriptions pr
      ON a.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    AND pr.drug IS NOT NULL
    AND (
      LOWER(pr.drug) LIKE '%nitroglycerin%' OR
      LOWER(pr.drug) LIKE '%isosorbide dinitrate%' OR
      LOWER(pr.drug) LIKE '%isosorbide mononitrate%' OR
      LOWER(pr.drug) LIKE '%nitrostat%' OR
      LOWER(pr.drug) LIKE '%nitro%' -- covers other nitrate formulations
    )
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
)
WHERE duration_days > 0;