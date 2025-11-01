WITH VitalSignInstability AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    SUM(CASE
      WHEN icu.value IS NOT NULL THEN 1
      ELSE 0
    END) AS instability_score
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS icu
  WHERE
    icu.itemid IN (
      SELECT
        itemid
      FROM
        `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE
        label IN ('Heart Rate', 'Respiratory Rate', 'Blood Pressure Mean', 'Blood Pressure Systolic', 'Blood Pressure Diastolic', 'Oxygen Saturation')
    ) AND icu.charttime BETWEEN TIMESTAMP_SUB(icu.intime, INTERVAL 72 HOUR) AND icu.intime
  GROUP BY
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
),
PatientCohort AS (
  SELECT
    hosp.subject_id,
    hosp.hadm_id,
    hosp.admittime,
    hosp.dischtime,
    hosp.deathtime,
    hosp.hospital_expire_flag,
    hosp.race,
    hosp.gender,
    hosp.anchor_age,
    diag.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS hosp
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
      ON hosp.hadm_id = diag.hadm_id
  WHERE
    hosp.gender = 'F' AND hosp.anchor_age BETWEEN 47 AND 57 AND diag.icd_code = 'I60'
),
ICUStays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN PatientCohort AS cohort
      ON icu.subject_id = cohort.subject_id AND icu.hadm_id = cohort.hadm_id
)
SELECT
  PERCENTILE_CONT(vsi.instability_score, 0.75) AS percentile_75,
  AVG(icu.los) AS avg_los,
  AVG(CASE
    WHEN icu.deathtime IS NOT NULL THEN 1
    ELSE 0
  END) AS mortality
FROM
  ICUStays AS icu
  INNER JOIN VitalSignInstability AS vsi
    ON icu.subject_id = vsi.subject_id AND icu.hadm_id = vsi.hadm_id AND icu.stay_id = vsi.stay_id
WHERE
  vsi.instability_score >= (
    SELECT
      PERCENTILE_CONT(instability_score, 0.9)
    FROM
      VitalSignInstability
  );