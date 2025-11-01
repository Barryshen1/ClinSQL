WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 58 AND 68
), RenalReplacementTherapy AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  ON
    p.subject_id = d.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
  ON
    d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 58 AND 68
    AND di.long_title LIKE '%renal replacement therapy%'
), VitalSigns AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.charttime,
    v.valuenum AS hr,
    v.valueuom AS hr_uom,
    m.valuenum AS map,
    m.valueuom AS map_uom
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS v
  ON
    s.stay_id = v.stay_id AND v.itemid = 3367 -- Heart Rate
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS m
  ON
    s.stay_id = m.stay_id AND m.itemid = 455 -- Mean Arterial Pressure
  WHERE
    s.stay_id IN (
      SELECT
        stay_id
      FROM
        RenalReplacementTherapy
    )
), InstabilityIndex AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    CASE
      WHEN hr > 100 AND map < 65 THEN 1
      ELSE 0
    END AS instability_flag
  FROM
    VitalSigns
  WHERE
    hr IS NOT NULL AND map IS NOT NULL
), HourlyInstability AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    DATE_TRUNC(charttime, HOUR) AS hour_start,
    COUNTIF(instability_flag = 1) AS instability_count
  FROM
    InstabilityIndex
  GROUP BY
    subject_id,
    hadm_id,
    stay_id,
    hour_start
), PatientStats AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    h.hospital_expire_flag,
    COUNTIF(hi.instability_count > 0) AS hypotensive_tachycardic_hours,
    APPROX_QUANTILES(hi.instability_count, [0.25, 0.5, 0.75, 0.9]) AS instability_percentiles
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS h
  ON
    s.hadm_id = h.hadm_id
  JOIN
    HourlyInstability AS hi
  ON
    s.subject_id = hi.subject_id AND s.hadm_id = hi.hadm_id AND s.stay_id = hi.stay_id
  WHERE
    s.stay_id IN (
      SELECT
        stay_id
      FROM
        Ren;