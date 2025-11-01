WITH PatientAges AS (
  SELECT
    subject_id,
    hadm_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 81 AND 91
), PatientICUStays AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime
  FROM
    PatientAges AS p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON p.subject_id = ic.subject_id AND p.hadm_id = ic.hadm_id
), SystolicBP AS (
  SELECT
    ps.subject_id,
    ps.hadm_id,
    ps.stay_id,
    ce.charttime,
    ce.valuenum AS systolic_bp
  FROM
    PatientICUStays AS ps
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ps.subject_id = ce.subject_id AND ps.hadm_id = ce.hadm_id AND ps.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220177 -- Systolic Blood Pressure
    AND ce.charttime BETWEEN ps.intime AND TIMESTAMP_ADD(ps.intime, INTERVAL 48 HOUR)
), AvgSystolicBP AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    AVG(systolic_bp) AS avg_systolic_bp
  FROM
    SystolicBP
  GROUP BY
    subject_id,
    hadm_id,
    stay_id
), PercentileCalculation AS (
  SELECT
    avg_systolic_bp,
    PERCENTILE_CONT(avg_systolic_bp, 0.5) OVER (ORDER BY avg_systolic_bp) AS median_avg_systolic_bp
  FROM
    AvgSystolicBP
)
SELECT
  avg_systolic_bp,
  median_avg_systolic_bp
FROM
  PercentileCalculation
ORDER BY
  avg_systolic_bp;