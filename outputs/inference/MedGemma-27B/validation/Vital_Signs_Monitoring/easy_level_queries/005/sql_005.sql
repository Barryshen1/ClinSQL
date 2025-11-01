WITH RelevantPatients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 59 AND 69
), SystolicBPMeasurements AS (
  SELECT
    rp.subject_id,
    ce.valuenum AS systolic_bp
  FROM
    RelevantPatients AS rp
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON rp.subject_id = ce.subject_id
  WHERE
    ce.itemid = 456 -- itemid for systolic blood pressure
)
SELECT
  PERCENTILE_CONT(systolic_bp, 0.75) AS percentile_75
FROM
  SystolicBPMeasurements;