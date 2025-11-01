SELECT
  MAX(duration_hours) AS max_nitrate_prescription_duration_hours
FROM (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.pharmacy_id,
    pr.drug,
    pr.route,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, HOUR) AS duration_hours
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON p.subject_id = pr.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON pr.hadm_id = adm.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND LOWER(pr.route) IN ('iv', 'oral', 'sublingual')
    AND (
      LOWER(pr.drug) LIKE '%nitroglycerin%'
      OR LOWER(pr.drug) LIKE '%isosorbide%'
      OR LOWER(pr.drug) LIKE '%dinitrate%'
      OR LOWER(pr.drug) LIKE '%mononitrate%'
    )
    AND TIMESTAMP_DIFF(pr.stoptime, pr.starttime, HOUR) > 0
);