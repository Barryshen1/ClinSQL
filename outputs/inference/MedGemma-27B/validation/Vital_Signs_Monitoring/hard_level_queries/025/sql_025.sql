WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age AS age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 55 AND 65
), PostArrestPatients AS (
  SELECT
    pi.subject_id,
    pi.admittime,
    pi.dischtime,
    pi.deathtime,
    pi.hospital_expire_flag
  FROM PatientInfo AS pi
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON pi.subject_id = d.subject_id AND pi.admittime = d.chartdate
  WHERE
    d.icd_code IN ('I469', 'I461', 'I468', 'I479', 'I471', 'I478', 'I489', 'I481', 'I482', 'I488', 'I499', 'I491', 'I498', 'I492', 'I493', 'I494', 'I495', 'I496', 'I497', 'I498', 'I499')
), ICUStays AS (
  SELECT
    pa.subject_id,
    pa.admittime,
    pa.dischtime,
    pa.deathtime,
    pa.hospital_expire_flag,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM PostArrestPatients AS pa
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON pa.subject_id = ic.subject_id AND pa.admittime = ic.hadm_id
), VitalSignInstability AS (
  SELECT
    icu.subject_id,
    icu.stay_id,
    icu.intime,
    SUM(CASE
      WHEN ce.itemid IN (220179, 220180, 220181, 220182, 220183, 220184, 220185, 220186, 220187, 220188, 220189, 220190, 220191, 220192, 220193, 220194, 220195, 220196, 220197, 220198, 220199, 220200) THEN 1 ELSE 0 END) AS instability_score
  FROM ICUStays AS icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.subject_id = ce.subject_id AND icu.stay_id = ce.stay_id
  WHERE
    ce.charttime BETWEEN icu.intime AND icu.intime + INTERVAL '24' HOUR
  GROUP BY
    icu.subject_id,
    icu.stay_id,
    icu.intime
), InstabilityPercentile AS (
  SELECT
    vsi.subject_id,
    vsi.stay_id,
    vsi.instability_score,
    PERCENTILE_CONT(vsi.instability_score, 0.1) OVER (ORDER BY vsi.instability_score) AS percentile_10,
    PERCENTILE_CONT(vsi.instability_score, 0.9) OVER (ORDER BY vsi.instability_score) AS percentile_90
  FROM;