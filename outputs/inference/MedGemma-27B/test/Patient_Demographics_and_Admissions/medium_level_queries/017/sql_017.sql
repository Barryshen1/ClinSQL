WITH PatientAge AS (
  SELECT
    p.subject_id,
    -- Calculate age in years based on admission time
    -- Corrected age calculation using DATE_DIFF
    DATE_DIFF(a.admittime, p.anchor_age, YEAR) AS age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
),
ICUStayInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.dischtime,
    a.deathtime,
    a.discharge_location
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON a.hadm_id = i.hadm_id
),
FilteredICUStay AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los,
    dischtime,
    deathtime,
    discharge_location
  FROM
    ICUStayInfo
  WHERE
    subject_id IN (
      SELECT
        subject_id
      FROM
        PatientAge
      WHERE
        age BETWEEN 38 AND 48
    )
    AND discharge_location IN ('HOME', 'FACILITY', 'IN-HOSPITAL DEATH')
)
SELECT
  discharge_location,
  AVG(los) AS mean_los,
  PERCENTILE_CONT(los, 0.5) AS median_los,
  PERCENTILE_CONT(los, 0.75) AS p75_los,
  PERCENTILE_CONT(los, 0.9) AS p90_los
FROM
  FilteredICUStay
GROUP BY
  discharge_location
ORDER BY
  discharge_location;