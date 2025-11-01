WITH PatientICUStays AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    ic.hadm_id,
    ic.stay_id,
    ic.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON ic.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
), PatientSBP AS (
  SELECT
    ps.subject_id,
    ps.hadm_id,
    ps.stay_id,
    ps.intime,
    ce.charttime,
    ce.valuenum AS systolic_bp
  FROM
    PatientICUStays AS ps
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON ps.subject_id = ce.subject_id
      AND ps.hadm_id = ce.hadm_id
      AND ps.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220177 -- Systolic Blood Pressure
    AND ce.charttime BETWEEN ps.intime AND TIMESTAMP_ADD(ps.intime, INTERVAL 24 HOUR)
)
SELECT
  CASE
    WHEN systolic_bp < 140 THEN '<140'
    WHEN systolic_bp BETWEEN 140 AND 159 THEN '140–159'
    ELSE '≥160'
  END AS bp_category,
  AVG(systolic_bp) AS mean_sbp,
  MEDIAN(systolic_bp) AS median_sbp,
  PERCENTILE_CONT(systolic_bp, 0.25) AS iqr_25,
  PERCENTILE_CONT(systolic_bp, 0.75) AS iqr_75
FROM
  PatientSBP
GROUP BY
  bp_category
ORDER BY
  bp_category;