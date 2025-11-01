WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age = 44
),
DKA_Admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%Diabetic Ketoacidosis%'
    AND d.seq_num = 1
),
ICU_Stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON a.hadm_id = i.hadm_id
  JOIN
    DKA_Admissions AS dka
    ON a.hadm_id = dka.hadm_id
  JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
  WHERE
    a.admission_type = 'EMERGENCY'
    AND a.hospital_expire_flag = 0
),
ProcedureCounts AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM
    ICU_Stays AS ic
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON ic.stay_id = pe.stay_id
  WHERE
    pe.starttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 24 HOUR)
  GROUP BY
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id
),
Quintiles AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.stay_id,
    pc.procedure_count,
    NTILE(5) OVER (ORDER BY pc.procedure_count) AS quintile
  FROM
    ProcedureCounts AS pc
),
FinalResults AS (
  SELECT
    q.quintile,
    COUNT(DISTINCT q.stay_id) AS number_of_stays,
    AVG(q.procedure_count) AS mean_procedure_count,
    MIN(q.procedure_count) AS min_procedure_count,
    MAX(q.procedure_count) AS max_procedure_count,
    AVG(ic.los) AS mean_icu_los_days,
    AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS hospital_mortality_percent
  FROM
    Quintiles AS q
  JOIN
    ICU_Stays AS ic
    ON q.stay_id = ic.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON q.hadm_id = a.hadm_id
  GROUP BY
    q.quintile
)
SELECT
  *
FROM
  FinalResults
ORDER BY
  quintile;