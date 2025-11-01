WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 87 AND 97
), ICUStays AS (
  SELECT
    s.subject_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN
    PatientAge AS pa
    ON s.subject_id = pa.subject_id
), SystolicBP AS (
  SELECT
    ic.subject_id,
    ic.stay_id,
    ic.charttime,
    ic.valuenum AS systolic_bp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ic
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ic.itemid = di.itemid
  WHERE
    di.label = 'Systolic blood pressure'
    AND ic.stay_id IN (
      SELECT
        stay_id
      FROM
        ICUStays
    )
), First24HourSBP AS (
  SELECT
    ic.subject_id,
    ic.stay_id,
    AVG(ic.systolic_bp) AS avg_systolic_bp
  FROM
    ICUStays AS s
  JOIN
    SystolicBP AS ic
    ON s.subject_id = ic.subject_id AND s.stay_id = ic.stay_id
  WHERE
    ic.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
  GROUP BY
    ic.subject_id,
    ic.stay_id
)
SELECT
  PERCENTILE_CONT(avg_systolic_bp, 0.99) AS percentile_99
FROM
  First24HourSBP;