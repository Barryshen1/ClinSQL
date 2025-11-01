WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 46
), ICUStays AS (
  SELECT
    p.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime
  FROM
    PatientInfo AS p
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
      ON p.subject_id = ic.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 41 AND 51
), RespiratoryRate AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ce.charttime,
    ce.valuenum AS rr_value
  FROM
    ICUStays AS ic
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON ic.subject_id = ce.subject_id
      AND ic.hadm_id = ce.hadm_id
      AND ic.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220187 -- Respiratory Rate
    AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
), RRStats AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    AVG(CASE WHEN rr_value < 12 THEN rr_value ELSE NULL END) AS avg_rr_lt12,
    AVG(CASE WHEN rr_value BETWEEN 12 AND 20 THEN rr_value ELSE NULL END) AS avg_rr_12_20,
    AVG(CASE WHEN rr_value BETWEEN 21 AND 29 THEN rr_value ELSE NULL END) AS avg_rr_21_29,
    AVG(CASE WHEN rr_value >= 30 THEN rr_value ELSE NULL END) AS avg_rr_ge30
  FROM
    RespiratoryRate
  GROUP BY
    subject_id,
    hadm_id,
    stay_id
), StrokeDiagnosis AS (
  SELECT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code LIKE 'I6%' -- Stroke codes
    AND seq_num = 1 -- Primary diagnosis
)
SELECT
  COUNT(DISTINCT ic.stay_id) AS total_patients,
  COUNT(DISTINCT CASE WHEN rs.avg_rr_lt12 IS NOT NULL THEN ic.stay_id END) AS patients_avg_rr_lt12,
  COUNT(DISTINCT CASE WHEN rs.avg_rr_12_20 IS NOT NULL THEN ic.stay_id END) AS patients_avg_rr_12_20,
  COUNT(DISTINCT CASE WHEN rs.avg_rr_21_29 IS NOT NULL THEN ic.stay_id END) AS patients_avg_rr_21_29,
  COUNT(DISTINCT CASE WHEN rs.avg_rr_ge30 IS NOT NULL THEN ic.stay_id END) AS patients_avg_rr_ge30,
  COUNT(DISTINCT CASE WHEN sd.subject_id IS NOT NULL THEN ic.stay_id END) AS stroke_patients
FROM
  ICUStays AS ic
  LEFT JOIN RRStats AS rs
    ON ic.subject_id = rs.subject_id
    AND ic.hadm_id = rs.hadm_id
    AND ic.stay_id = rs.stay_id
  LEFT JOIN StrokeDiagnosis AS sd
    ON ic.subject_id = sd.subject_id
    AND ic.hadm_id = sd.hadm_id
GROUP BY
  ic.stay_id;