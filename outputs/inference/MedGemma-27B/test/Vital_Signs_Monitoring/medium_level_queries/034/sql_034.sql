WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 37 AND 47
), ICUStays AS (
  SELECT
    p.subject_id,
    ic.stay_id,
    ic.intime,
    ic.outtime
  FROM
    PatientInfo AS p
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
      ON p.subject_id = ic.subject_id
), NonInvasiveVentilation AS (
  SELECT
    ic.subject_id,
    ic.stay_id
  FROM
    ICUStays AS ic
    INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
      ON ic.subject_id = pe.subject_id AND ic.stay_id = pe.stay_id
  WHERE
    pe.itemid IN (
      SELECT
        itemid
      FROM
        `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE
        label LIKE '%CPAP%' OR label LIKE '%BiPAP%'
    )
), MaxDiastolicBP AS (
  SELECT
    niv.subject_id,
    niv.stay_id,
    MAX(ce.valuenum) AS max_diastolic_bp
  FROM
    NonInvasiveVentilation AS niv
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON niv.subject_id = ce.subject_id AND niv.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220187 -- Diastolic Blood Pressure
  GROUP BY
    niv.subject_id,
    niv.stay_id
)
SELECT
  PERCENTILE_CONT(0.25, max_diastolic_bp) AS percentile_25
FROM
  MaxDiastolicBP;