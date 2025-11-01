SELECT 
  MAX(duration_days) AS max_nitrate_duration_days
FROM (
  SELECT 
    pr.subject_id,
    DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR) / 24.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pa
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pa.subject_id = pr.subject_id
  WHERE pa.gender = 'F'
    AND pa.anchor_age BETWEEN 80 AND 90
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
    AND (
      UPPER(pr.drug) LIKE '%NITROGLYCERIN%' OR
      UPPER(pr.drug) LIKE '%ISOSORBIDE%' OR
      UPPER(pr.drug) LIKE '%NITRATE%'
    )
    AND UPPER(pr.route) IN ('IV', 'ORAL', 'SUBLINGUAL')
) t;