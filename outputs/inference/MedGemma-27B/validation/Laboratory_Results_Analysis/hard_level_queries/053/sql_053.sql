WITH PatientCohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
), LabInstability AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom,
    dli.label AS lab_name
  FROM PatientCohort AS pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON pc.subject_id = le.subject_id AND pc.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    le.charttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 72 HOUR)
    AND dli.label IN ('Creatinine', 'Potassium', 'Platelet Count', 'Hemoglobin', 'WBC Count')
), LabInstabilityScore AS (
  SELECT
    subject_id,
    hadm_id,
    AVG(
      CASE
        WHEN ABS(valuenum - LAG(valuenum, 1, valuenum) OVER (PARTITION BY subject_id, hadm_id, lab_name ORDER BY charttime)) > 0.5 THEN 1
        ELSE 0
      END
    ) AS instability_score
  FROM LabInstability
  GROUP BY
    subject_id,
    hadm_id
), CohortStats AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    a.hospital_expire_flag,
    a.dischtime,
    a.admittime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM PatientCohort AS pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pc.subject_id = a.subject_id AND pc.hadm_id = a.hadm_id
), CriticalRates AS (
  SELECT
    cs.subject_id,
    cs.hadm_id,
    AVG(
      CASE
        WHEN le.valuenum > 1.5 THEN 1
        ELSE 0
      END
    ) AS critical_cr_rate,
    AVG(
      CASE
        WHEN le.valuenum > 5.5 THEN 1
        ELSE 0
      END
    ) AS critical_k_rate,
    AVG(
      CASE
        WHEN le.valuenum < 150000 THEN 1
        ELSE 0
      END
    ) AS critical_platelet_rate,
    AVG(
      CASE
        WHEN le.valuenum < 7 THEN 1
        ELSE 0
      END
    ) AS critical_hgb_rate,
    AVG(
      CASE
        WHEN le.valuenum > 15 THEN 1
        ELSE 0
      END
    ) AS critical_wbc_rate
  FROM CohortStats AS cs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON cs.subject_id = le.subject_id AND cs.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label IN ('Creatinine', 'Potassium', 'Platelet Count', 'Hemoglobin', 'WBC Count')
    AND le.charttime BETWEEN cs.admittime AND TIMESTAMP_ADD;