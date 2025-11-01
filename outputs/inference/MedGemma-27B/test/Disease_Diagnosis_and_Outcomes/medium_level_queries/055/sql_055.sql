WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.gender,
    p.anchor_age,
    CASE
      WHEN p.anchor_age BETWEEN 71 AND 81 THEN 1
      ELSE 0
    END AS age_group_flag,
    CASE
      WHEN d.icd_code = '996.6' THEN 1
      ELSE 0
    END AS complications_of_care_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND d.icd_code = '996.6' -- Complications of care
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.los,
    i.first_careunit,
    i.last_careunit,
    i.intime,
    i.outtime,
    i.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.icustays` AS i
    ON a.hadm_id = i.hadm_id
), ICUStayInfo AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los
  FROM
    `physionet-data.mimiciv_3_1_hosp.icustays`
), LOSQuartile AS (
  SELECT
    subject_id,
    hadm_id,
    NTILE(4) OVER (PARTITION BY subject_id ORDER BY los) AS los_quartile
  FROM
    `physionet-data.mimiciv_3_1_hosp.icustays`
), MechanicalVentilation AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    MAX(CASE WHEN itemid = 50919 THEN value ELSE NULL END) AS mechanical_ventilation
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid = 50919
  GROUP BY
    subject_id,
    hadm_id,
    stay_id
), Vasopressors AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    MAX(CASE WHEN itemid = 30301 THEN value ELSE NULL END) AS vasopressors
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid = 30301
  GROUP BY
    subject_id,
    hadm_id,
    stay_id
), RRT AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    MAX(CASE WHEN itemid = 50919 THEN value ELSE NULL END) AS rrt
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid = 50919
  GROUP BY
    subject_id,
    hadm_id,
    stay_id
)
SELECT
  ai.subject_id,
  ai.hadm_id,
  ai.gender,
  ai.anchor_age,
  ai.age_group_flag,
  ai.complications_of_care_flag,
  ai.admittime,
  ai.dischtime,
  ai.deathtime,
  ai.hospital_expire_flag,
  ai.los,
  ai.first_careunit,
  ai.last_careunit,
  ai.intime;