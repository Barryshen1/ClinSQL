WITH PatientAge AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN anchor_age >= 55 AND anchor_age <= 65 THEN 1
      ELSE 0
    END AS is_age_55_65
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
), PatientGender AS (
  SELECT
    subject_id,
    CASE
      WHEN gender = 'M' THEN 1
      ELSE 0
    END AS is_male
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
), ICUStayInfo AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    ic.first_careunit,
    ic.last_careunit,
    pa.is_age_55_65,
    pg.is_male,
    h.hospital_expire_flag AS mortality
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  LEFT JOIN PatientAge AS pa
    ON ic.subject_id = pa.subject_id
  LEFT JOIN PatientGender AS pg
    ON ic.subject_id = pg.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS h
    ON ic.hadm_id = h.hadm_id
), HFNC_Events AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.charttime,
    di.label AS device_label
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ic
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ic.itemid = di.itemid
  WHERE
    di.label LIKE '%HFNC%'
), HFNC_Within_24h AS (
  SELECT
    isi.subject_id,
    isi.hadm_id,
    isi.stay_id,
    isi.intime,
    isi.mortality,
    he.charttime AS hfnc_charttime
  FROM ICUStayInfo AS isi
  LEFT JOIN HFNC_Events AS he
    ON isi.subject_id = he.subject_id AND isi.hadm_id = he.hadm_id AND isi.stay_id = he.stay_id
  WHERE
    isi.is_age_55_65 = 1 AND isi.is_male = 1
    AND he.charttime BETWEEN isi.intime AND TIMESTAMP_ADD(isi.intime, INTERVAL 24 HOUR)
), InstabilityScore AS (
  SELECT
    isi.subject_id,
    isi.hadm_id,
    isi.stay_id,
    isi.intime,
    isi.mortality,
    ce.charttime,
    ce.valuenum AS instability_score
  FROM ICUStayInfo AS isi
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON;