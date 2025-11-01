WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    subject_id = 42 -- Specific patient ID
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
  WHERE
    a.admission_type = 'EMERGENCY' -- Filter for transfer-ins (assuming emergency admission implies transfer-in)
), StayInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    AdmissionInfo AS a
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON a.subject_id = i.subject_id
    AND a.hadm_id = i.hadm_id
), DischargeInfo AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.los,
    CASE
      WHEN a.discharge_location = 'HOME' THEN 'HOME'
      WHEN a.discharge_location IN ('SNF', 'REHAB', 'LTACH') THEN 'SNF/REHAB/LTACH'
      WHEN a.hospital_expire_flag = 1 THEN 'IN-HOSPITAL MORTALITY'
      ELSE 'OTHER'
    END AS discharge_category
  FROM
    StayInfo AS s
  JOIN
    AdmissionInfo AS a
    ON s.subject_id = a.subject_id
    AND s.hadm_id = a.hadm_id
)
SELECT
  discharge_category,
  COUNT(DISTINCT subject_id) AS n,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 5)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(los, 5)[OFFSET(2)] AS median,
  APPROX_QUANTILES(los, 5)[OFFSET(3)] AS p75,
  APPROX_QUANTILES(los, 5)[OFFSET(4)] AS p90,
  APPROX_QUANTILES(los, 5)[OFFSET(5)] AS p95,
  PERCENTILE_CONT(los, 0.05) AS percentile_rank_5_day_stay
FROM
  DischargeInfo
WHERE
  los = 5
GROUP BY
  discharge_category
ORDER BY
  discharge_category;