WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age >= 68
    AND p.anchor_age <= 78
    AND a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'PHYSICIAN REFERRAL'
    AND a.insurance = 'MEDICARE'
    AND a.discharge_location = 'HOME'
    AND a.hospital_expire_flag = 0
  ),
VitalSignInstability AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    v.charttime,
    v.itemid,
    v.value,
    v.valuenum,
    v.valueuom,
    CASE
      WHEN v.itemid = 220179 THEN 1 -- Heart Rate
      WHEN v.itemid = 455 THEN 1 -- Respiratory Rate
      WHEN v.itemid = 456 THEN 1 -- Systolic Blood Pressure
      WHEN v.itemid = 457 THEN 1 -- Diastolic Blood Pressure
      ELSE 0
    END AS is_vital,
    CASE
      WHEN v.itemid = 220179 AND v.valuenum > 100 THEN 1
      WHEN v.itemid = 455 AND v.valuenum > 25 THEN 1
      WHEN v.itemid = 456 AND v.valuenum < 90 THEN 1
      WHEN v.itemid = 457 AND v.valuenum < 60 THEN 1
      ELSE 0
    END AS instability_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS v
  WHERE
    v.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientCohort
    )
    AND v.hadm_id IN (
      SELECT
        hadm_id
      FROM
        PatientCohort
    )
    AND v.itemid IN (
      220179, 455, 456, 457
    )
    AND v.charttime BETWEEN
      (
        SELECT
          min(intime)
        FROM
          `physionet-data.mimiciv_3_1_icu.icustays` AS i
        WHERE
          i.subject_id = v.subject_id AND i.hadm_id = v.hadm_id
      ) AND (
        SELECT
          max(outtime)
        FROM
          `physionet-data.mimiciv_3_1_icu.icustays` AS i
        WHERE
          i.subject_id = v.subject_id AND i.hadm_id = v.hadm_id
      )
  ),
InstabilityQuartiles AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    SUM(instability_flag) AS instability_score,
    NTILE(4) OVER (ORDER BY SUM(instability_flag)) AS quartile
  FROM
    VitalSignInstability
  GROUP BY
    subject_id,
    hadm_id,
    stay_id
  ),
ICUStayInfo AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    s.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  WHERE
    s.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientCohort
    )
    AND s.hadm_id IN (
      SELECT
        hadm_id
      FROM
        PatientCohort
    )
  ),;