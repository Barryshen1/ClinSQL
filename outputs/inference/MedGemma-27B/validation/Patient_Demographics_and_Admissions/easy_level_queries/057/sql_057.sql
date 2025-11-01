WITH PatientStroke AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
    AND d.icd_code LIKE 'I6%' -- ICD-10 codes for stroke
),
ICUStays AS (
  SELECT
    s.subject_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los -- Add the los column here
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  WHERE
    s.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientStroke
    )
    AND s.first_careunit IS NOT NULL -- Ensure it's a valid ICU stay
)
SELECT
  PERCENTILE_CONT(0.25, los) AS IQR_25,
  PERCENTILE_CONT(0.75, los) AS IQR_75
FROM
  ICUStays;