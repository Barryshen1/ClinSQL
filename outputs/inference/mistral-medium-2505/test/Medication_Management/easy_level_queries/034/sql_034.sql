WITH female_patients_51_61 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 51 AND 61
),

prescription_durations AS (
  SELECT
    p.subject_id,
    p.drug,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    female_patients_51_61 fp ON p.subject_id = fp.subject_id
  WHERE
    p.drug IN ('hydralazine', 'isosorbide dinitrate')
    AND p.stoptime IS NOT NULL  -- Exclude ongoing prescriptions
)

SELECT
  drug,
  MAX(duration_days) AS longest_duration_days
FROM
  prescription_durations
GROUP BY
  drug
ORDER BY
  longest_duration_days DESC;