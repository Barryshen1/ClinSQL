WITH dhp_duration AS (
  SELECT
    (TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND) / 86400.0) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pr.subject_id = adm.subject_id
   AND pr.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pr.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 81 AND 91
    AND (
      LOWER(pr.drug) LIKE '%amlodipine%' OR
      LOWER(pr.drug) LIKE '%nifedipine%' OR
      LOWER(pr.drug) LIKE '%felodipine%' OR
      LOWER(pr.drug) LIKE '%nicardipine%' OR
      LOWER(pr.drug) LIKE '%nimodipine%' OR
      LOWER(pr.drug) LIKE '%nisoldipine%' OR
      LOWER(pr.drug) LIKE '%clevidipine%'
    )
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
)

SELECT DISTINCT
  PERCENTILE_CONT(duration_days, 0.25) OVER () AS p25_duration_days
FROM dhp_duration;