WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age = 57
),
TransferredPatients AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.admission_location = 'TRANSFER FROM HOSPITAL'
),
ICUStays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  WHERE
    i.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
    AND i.hadm_id IN (
      SELECT
        hadm_id
      FROM
        TransferredPatients
    )
),
FiveDayLOS AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.los AS actual_los,
    CASE
      WHEN ic.los <= 5
      THEN ic.los
      ELSE 5
    END AS five_day_los
  FROM
    ICUStays AS ic
)
SELECT
  AVG(five_day_los) AS mean_5day_los,
  STDDEV(five_day_los) AS sd_5day_los,
  APPROX_QUANTILES(five_day_los, 100) AS percentile_rank_5day_los
FROM
  FiveDayLOS
WHERE
  FiveDayLOS.subject_id IN (
    SELECT
      p.subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    WHERE
      p.gender = 'F' AND p.anchor_age BETWEEN 52 AND 62
  )
  AND FiveDayLOS.hadm_id IN (
    SELECT
      a.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    WHERE
      a.admission_location = 'TRANSFER FROM HOSPITAL'
  )
  AND FiveDayLOS.actual_los > 0;