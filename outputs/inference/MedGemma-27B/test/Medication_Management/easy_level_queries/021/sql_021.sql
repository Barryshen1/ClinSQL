WITH relevant_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug,
    p.dose_val_rx,
    p.dose_unit_rx,
    p.formulary_drug_cd,
    pa.gender,
    pa.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pa
    ON p.subject_id = pa.subject_id
  WHERE
    p.drug LIKE 'Atorvastatin%'
    AND p.formulary_drug_cd = 'ATORVASTATIN'
    AND (
      p.dose_val_rx = 40
      OR p.dose_val_rx = 80
    )
    AND p.dose_unit_rx = 'mg'
    AND pa.gender = 'F'
    AND pa.anchor_age BETWEEN 75 AND 85
)
SELECT
  PERCENTILE_CONT(0.25, duration) AS q1,
  PERCENTILE_CONT(0.75, duration) AS q3,
  PERCENTILE_CONT(0.75, duration) - PERCENTILE_CONT(0.25, duration) AS IQR
FROM (
  SELECT
    subject_id,
    hadm_id,
    TIMESTAMP_DIFF(stoptime, starttime, DAY) AS duration
  FROM
    relevant_prescriptions
  WHERE
    stoptime IS NOT NULL
);