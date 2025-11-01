WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
), ICUStayInfo AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
), DiagnosisInfo AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.seq_num,
    d.chartdate
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE
    d.icd_version = 9
), SepsisDiagnosis AS (
  SELECT
    di.subject_id,
    di.hadm_id
  FROM DiagnosisInfo AS di
  WHERE
    di.icd_code IN ('001', '0010', '0011', '0012', '0013', '0014', '0015', '0016', '0017', '0018', '0019', '995', '9950', '9951', '9952', '9953', '9954', '9955', '9956', '9957', '9958', '9959')
), DiagnosticUtilization AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    COUNT(DISTINCT di.icd_code) AS diagnostic_utilization
  FROM DiagnosisInfo AS di
  WHERE
    di.chartdate BETWEEN di.hadm_id.admittime AND TIMESTAMP_ADD(di.hadm_id.admittime, INTERVAL 24 HOUR)
  GROUP BY
    di.subject_id,
    di.hadm_id
), FinalCohort AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    pi.gender,
    pi.anchor_age,
    pi.admittime,
    pi.dischtime,
    pi.deathtime,
    pi.hospital_expire_flag,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    sd.subject_id AS sepsis_subject_id,
    sd.hadm_id AS sepsis_hadm_id,
    du.diagnostic_utilization
  FROM PatientInfo AS pi
  INNER JOIN ICUStayInfo AS ic
    ON pi.subject_id = ic.subject_id AND pi.hadm_id = ic.hadm_id
  INNER JOIN SepsisDiagnosis AS sd
    ON pi.subject_id = sd.subject_id AND pi.hadm_id = sd.hadm_id
  INNER JOIN DiagnosticUtilization AS du
    ON pi.subject_id = du.subject_id AND pi.hadm_id = du.hadm_id
  WHERE
    pi.gender = 'M'
    AND pi.anchor_age BETWEEN 90 AND 100
    AND ic.intime BETWEEN pi.admittime AND TIMESTAMP_ADD(pi.admittime, INTERVAL 24 HOUR)
), FinalStats AS (
  SELECT
    STDDEV(diagnostic_utilization) AS sd_diagnostic_utilization,
    PERCENTILE_CONT(0.75, diagnostic_utilization) AS p75_diagnostic_utilization,
    PERCENTILE_CONT(0.95, diagnostic_utilization) AS p95_diagnostic_utilization,
    AVG(los) AS avg_los,
    COUNT(CASE WHEN hospital_expire_flag = TRUE THEN 1;