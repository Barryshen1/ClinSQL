WITH PatientInfo AS (
  SELECT
    subject_id,
    hadm_id,
    gender,
    anchor_age,
    admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    gender = 'M' AND anchor_age BETWEEN 76 AND 86
), DiagnosisInfo AS (
  SELECT
    subject_id,
    hadm_id,
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code = 'I21.0' -- Acute myocardial infarction
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
), ProcedureInfo AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    chartdate,
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedureevents`
), ProcedureCount AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    COUNT(DISTINCT icd_code) AS distinct_procedure_count
  FROM
    ProcedureInfo
  WHERE
    chartdate BETWEEN intime AND TIMESTAMP_ADD(intime, INTERVAL 24 HOUR)
  GROUP BY
    subject_id,
    hadm_id,
    stay_id
), QuartileAssignment AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    distinct_procedure_count,
    NTILE(4) OVER (ORDER BY distinct_procedure_count) AS procedure_quartile
  FROM
    ProcedureCount
), FinalData AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    q.stay_id,
    q.procedure_quartile,
    q.distinct_procedure_count,
    i.los,
    a.hospital_expire_flag
  FROM
    QuartileAssignment AS q
  JOIN
    ICUStayInfo AS i
    ON q.subject_id = i.subject_id AND q.hadm_id = i.hadm_id AND q.stay_id = i.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON q.subject_id = a.subject_id AND q.hadm_id = a.hadm_id
)
SELECT
  procedure_quartile,
  AVG(distinct_procedure_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS hospital_mortality_percent
FROM
  FinalData
GROUP BY
  procedure_quartile
ORDER BY
  procedure_quartile;