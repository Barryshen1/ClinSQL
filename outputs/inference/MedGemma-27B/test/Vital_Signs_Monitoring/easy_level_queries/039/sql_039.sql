WITH PatientInfo AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 56
),
FirstICUAdmission AS (
  SELECT
    p.subject_id,
    i.stay_id,
    i.intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON a.hadm_id = i.hadm_id
  JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
  WHERE
    a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.hospital_expire_flag = 0
),
FirstRR AS (
  SELECT
    fia.subject_id,
    fia.stay_id,
    ce.value AS respiratory_rate
  FROM
    FirstICUAdmission AS fia
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON fia.subject_id = ce.subject_id AND fia.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE
    di.label = 'Respiratory Rate'
    AND ce.charttime = (
      SELECT
        MIN(charttime)
      FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce_inner
      WHERE
        ce_inner.subject_id = ce.subject_id AND ce_inner.stay_id = ce.stay_id AND di.itemid = ce_inner.itemid
    )
)
SELECT
  PERCENTILE_CONT(respiratory_rate, 0.25)
FROM
  FirstRR;