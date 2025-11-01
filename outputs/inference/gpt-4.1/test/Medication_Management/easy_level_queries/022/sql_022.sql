WITH dihydropyridine_ccb_drugs AS (
  SELECT 'amlodipine' AS drug UNION ALL
  SELECT 'nifedipine' UNION ALL
  SELECT 'felodipine' UNION ALL
  SELECT 'nicardipine' UNION ALL
  SELECT 'isradipine' UNION ALL
  SELECT 'clevidipine' UNION ALL
  SELECT 'lercanidipine' UNION ALL
  SELECT 'manidipine' UNION ALL
  SELECT 'nimodipine'
),
target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 59 AND 69
)
SELECT
  APPROX_QUANTILES(duration_days, 2)[OFFSET(1)] AS median_duration_days
FROM (
  SELECT
    p.subject_id,
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    INNER JOIN target_patients p
      ON pr.subject_id = p.subject_id
    INNER JOIN dihydropyridine_ccb_drugs dccbd
      ON LOWER(pr.drug) LIKE CONCAT('%', dccbd.drug, '%')
  WHERE
    pr.drug_type = 'Inpatient'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
);