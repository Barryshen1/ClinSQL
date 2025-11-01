WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 82 AND 92
),
MaxMAPPerStay AS (
  SELECT
    p.subject_id,
    h.hadm_id,
    MAX(ce.valuenum) AS max_map
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS h
    JOIN PatientInfo AS p ON h.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce ON h.hadm_id = ce.hadm_id
    WHERE
      ce.itemid = 455 -- MAP (Mean Arterial Pressure) itemid
      AND ce.valuenum IS NOT NULL
  GROUP BY
    p.subject_id,
    h.hadm_id
)
SELECT
  PERCENTILE_CONT(max_map, 0.5) AS median_max_map
FROM
  MaxMAPPerStay;