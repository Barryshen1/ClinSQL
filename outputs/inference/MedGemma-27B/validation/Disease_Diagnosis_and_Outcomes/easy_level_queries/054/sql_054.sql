WITH relevant_patients AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 56
  ),
  stroke_patients AS (
    SELECT
      d.subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    WHERE
      d.subject_id IN (SELECT subject_id FROM relevant_patients)
      AND d.icd_code LIKE 'I6%' -- ICD-10 codes for hemorrhagic stroke
      AND d.seq_num = 1 -- Primary diagnosis
  ),
  icu_stays AS (
    SELECT
      ic.subject_id,
      ic.hadm_id,
      ic.stay_id,
      ic.intime,
      ic.outtime
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    WHERE
      ic.subject_id IN (SELECT subject_id FROM stroke_patients)
  ),
  los_calculation AS (
    SELECT
      ic.subject_id,
      ic.hadm_id,
      ic.stay_id,
      TIMESTAMP_DIFF(ic.outtime, ic.intime, DAY) AS los_days
    FROM
      icu_stays AS ic
  )
SELECT
  STDDEV(los_days)
FROM
  los_calculation;