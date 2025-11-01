WITH PatientDiagnosis AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    di.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON p.subject_id = di.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND di.icd_code = 'I26.99' -- Pulmonary embolism code
), ICUStayInfo AS (
  SELECT
    ps.subject_id,
    ps.anchor_age,
    ps.gender,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    ic.first_careunit,
    ic.last_careunit,
    ic.hadm_id
  FROM PatientDiagnosis AS ps
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON ps.subject_id = ic.subject_id
), DiagnosticUtilization AS (
  SELECT
    isi.subject_id,
    isi.stay_id,
    isi.hadm_id, -- Added hadm_id here
    COUNT(DISTINCT ce.itemid) AS diagnostic_utilization_score
  FROM ICUStayInfo AS isi
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON isi.subject_id = ce.subject_id AND isi.stay_id = ce.stay_id
  WHERE
    ce.charttime BETWEEN isi.intime AND TIMESTAMP_ADD(isi.intime, INTERVAL 24 HOUR)
  GROUP BY
    isi.subject_id,
    isi.stay_id,
    isi.hadm_id -- Added hadm_id here
), GeneralICUPopulation AS (
  SELECT
    ic.subject_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    ic.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
), MortalityInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
)
SELECT
  AVG(du.diagnostic_utilization_score) AS avg_diagnostic_utilization_score,
  PERCENTILE_CONT(du.diagnostic_utilization_score, 0.75) AS p75_diagnostic_utilization_score,
  AVG(gip.los) AS avg_icu_los,
  AVG(mi.hospital_expire_flag) AS avg_in_hospital_mortality
FROM DiagnosticUtilization AS du
INNER JOIN GeneralICUPopulation AS gip
  ON du.subject_id = gip.subject_id AND du.stay_id = gip.stay_id
INNER JOIN MortalityInfo AS mi
  ON du.subject_id = mi.subject_id AND du.hadm_id = mi.hadm_id;